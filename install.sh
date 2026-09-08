#!/usr/bin/env bash
#
# Kinglet Pioneer — installer
#
# Installs the toolkit into a Unity project: agents, commands, skills, hooks, rules, templates,
# settings, and a generated CLAUDE.md. One repo, one script, no prerequisites beyond Unity itself.
#
# Usage:
#   ./install.sh [--project-dir <path>] [--client claude|codex] [--with-mcp]
#                [--with-input-system] [--codex-trust] [--yes] [--dry-run]
#
#   --project-dir <path>  Target Unity project root (default: current directory)
#   --client <name>       claude (default) or codex. `codex` ALSO writes the Codex CLI layer:
#                         AGENTS.md, the .agents/skills root, .codex/hooks.json and the
#                         .codex/config.toml MCP row. It never removes anything Claude Code reads.
#   --with-mcp            Also add the CoplayDev Unity MCP package to Packages/manifest.json
#   --with-input-system   Also add Unity's New Input System package to Packages/manifest.json
#   --codex-trust         With --client codex, also grant Codex hook trust by writing one
#                         [hooks.state."<key>"] table per hook into $CODEX_HOME/config.toml
#                         (default ~/.codex). This writes your HOME, not the project, so it is
#                         opt-in: without it the hooks are registered and will not run.
#   --no-codex-trust      Never ask, never write the home. The default under --yes.
#   --yes                 Non-interactive; take the safe default at every prompt
#   --dry-run             Report what would happen; write nothing
#   -h, --help            Show this help
#
# .claude/state/install-receipt.tsv records every file the toolkit owns, with its checksum, so
# uninstall removes exactly what is ours and leaves everything else alone — files you edited, files
# you wrote, and a .gitignore you already had. One this installer CREATED is ours until you edit it.
#
set -euo pipefail

# ── Colors ───────────────────────────────────────────────────────────────────
if [ -t 1 ]; then
  RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[0;33m'; BLUE=$'\033[0;34m'; CYAN=$'\033[0;36m'; BOLD=$'\033[1m'; NC=$'\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; BLUE=''; CYAN=''; BOLD=''; NC=''
fi
info() { printf '%s\n' "${BLUE}==>${NC} $*"; }
ok()   { printf '%s\n' "${GREEN} ok${NC}  $*"; }
warn() { printf '%s\n' "${YELLOW}warn${NC} $*"; }
err()  { printf '%s\n' "${RED}err ${NC} $*" >&2; }
die()  { err "$*"; exit 1; }

usage() { sed -n '3,29p' "$0" | sed 's/^# \{0,1\}//'; exit 0; }

# ── Work this run was asked for and did not do ───────────────────────────────
# ONE ACCUMULATOR, ONE EMITTER, AND THE REASON IS THAT MANY BRANCHES CAN ABANDON WORK AND EXACTLY
# ONE OF THEM USED TO REACH THE USER'S SUMMARY. `Installation complete.` and exit 0 are true
# of every one of them — the payload lands, the receipt is written — so the only trace of an
# abandoned --with-* flag, an ungenerated CLAUDE.md, an unwritten .gitignore or a hook that will
# never fire was a warn line up to five hundred lines above the green banner, in output nobody
# scrolls back through and no caller can act on. `MANIFEST_DECLINED` was this mechanism for one of
# them; this is the same mechanism with the rest routed through it.
#
# THERE ARE FEWER RECORDING POINTS THAN THERE ARE BRANCHES, and every collapse is one outcome reached
# more than one way: each `add_manifest_dependency` site fires for either --with-* flag, and
# CLAUDE.md's `skipped` is reached by several arms that differ only in which warn line printed.
# THE NUMBER IS NOT WRITTEN HERE, and it was — `four ways`, which went stale inside the commit that
# split `refresh-failed` out of `skipped` and corrected the same figure at the recording point and
# inside the entry while leaving this copy. Three sites, one number, one edit: exactly the shape the
# paragraph below forbids, committed against the paragraph below. Derive it from the arms that assign
# the value if you need it.
#
# NO COUNT IS WRITTEN HERE, and that is this comment's own rule applied to itself — the number went
# stale at the emitter within one round of being written down, in the file that forbids quoting it.
# Exclude comments when you derive it, or the derivation counts the very line you are reading. It
# did, for the length of one measurement:
#
#   awk '!/^[[:space:]]*#/ && /note_not_done "/ { n++ } END { print n + 0 }' install.sh
#
# THE CONTRACT THIS BLOCK MAKES GOOD ON IS WRITTEN DOWN, in MCP-SETUP.md § "What install.sh's exit
# status means" — the one document of the three candidates that installs into a project. It says
# exit 0 means the run reached its end and reported what it did, and that everything asked for and
# not done is listed HERE. A new abandonment site that only warns falsifies that sentence, so a new
# site is a `note_not_done` call and not just a `warn`.
#
# WHAT DOES NOT BELONG HERE: a file kept because YOU edited it. The payload landed, the file is on
# disk, and its contents are your own choice — that is the `keeping yours` report a few steps up,
# not work the installer abandoned. A keep enters this list only where it leaves a SECOND artifact
# absent or inert (a kept settings.json leaves this version's hooks on disk and unregistered) or
# where nobody chose anything (a receipt origin this installer cannot read).
#
# ONE LINE PER ENTRY. A site that needs a remedy sentence puts it on the same line: the block is read
# once, at the end of a run, by someone deciding what to do next, and an entry split across lines
# stops being countable by eye.
NOT_DONE=""
note_not_done() { NOT_DONE="${NOT_DONE}$1"$'\n'; }
# `if`, not `[ -n "$NOT_DONE" ] || return`: a false test as a function's last command is a `set -e`
# kill at the CALL SITE, and one of the two call sites is the abort path, where the run is supposed
# to end 0. `while read` over a here-string rather than a pipe — the loop drains its input either
# way, so there is no SIGPIPE hazard, but a here-string keeps the body out of a subshell.
#
# NOT REACHED ON A DRY RUN. Step 4's unreadable-origin scan runs before the `Would install:` block
# and can call note_not_done there, but that block exits 0 without calling this — deliberately: a
# dry run does not abandon work, it announces what a real run would do, and it has its own line for
# that same state. Nothing else accumulates before the dry-run exit.
print_not_done() {
  if [ -n "$NOT_DONE" ]; then
    printf '\n%s\n' "${BOLD}${YELLOW}Not done:${NC}"
    while IFS= read -r nd_line; do
      if [ -n "$nd_line" ]; then printf '  %s\n' "$nd_line"; fi
    done <<< "$NOT_DONE"
  fi
}

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TOOLKIT_VERSION="$(cat "$SCRIPT_DIR/.claude/VERSION" 2>/dev/null || echo unknown)"

MCP_PKG_NAME="com.coplaydev.unity-mcp"
# Pinned to v10.1.0's commit (see .claude/UPSTREAM), not #main — which version a user got used to
# depend on the day they ran --with-mcp.
#
# It must be a FULL 40-character SHA or a tag. UPM rejects a short hash outright:
#   "Could not clone. Make sure [<ref>] is a valid branch name, tag or full commit hash"
#
# The previous value here, `a4c2d0a84573`, was neither. It was read off the Unity package cache
# directory `Library/PackageCache/com.coplaydev.unity-mcp@a4c2d0a84573` and recorded as a commit.
# That suffix is Unity's own content hash, not a git revision — the same cache directory appears
# with that identical suffix after resolving from this pin, and registry packages that have no git
# repository at all carry one too (`com.unity.2d.animation@6e14714a57c6`). GitHub returns
# "No commit found for SHA" for it. So --with-mcp could never have worked, and did not, until it
# was run end to end on 2026-07-30.
MCP_PKG_URL="https://github.com/CoplayDev/unity-mcp.git?path=/MCPForUnity#c14de1e6dc01ab42d2bb358730cff954bce0ce6b"

# unity-specifics.md makes the New Input System non-negotiable and block-legacy-input.sh blocks
# `Input.*` outright. Without the package a compliant script fails to compile — and a compile
# error also aborts Unity's -executeMethod, so Editor automation stops too (smoke-pass.md §6c).
# It is a first-party Unity registry package, so a version pin (not a git URL) is all it needs.
# Pinned to 1.18.0 — the version measured in a real, working Unity 6 project (URP, 1073 C# files,
# Unity 6000.0.68f1) per docs/research/pioneer/smoke-pass.md §9. It is the only version of this
# package this toolkit has been observed alongside in a working Unity 6 project.
INPUT_SYSTEM_PKG_NAME="com.unity.inputsystem"
INPUT_SYSTEM_PKG_VERSION="1.18.0"

RECEIPT_REL=".claude/state/install-receipt.tsv"
# Read by the Codex trust step, by Step 8e's carry-forward, and by the dry run's
# Codex-layer announcement — all three outside the `--client codex` block, so it is
# declared here rather than beside its writer. See the note above that writer.
CODEX_TRUST_REL=".claude/state/codex-trust.tsv"

# ── Which receipted paths only a `--client codex` run writes ─────────────────
#
# ONE DEFINITION, READ HERE AND IN A DIFFERENT FILE. It answers exactly one question — *will a plain
# `install.sh` write this path?* — and the answer decides three behaviours: which previous-receipt
# rows Step 8e carries forward, what the dry run announces, and (in `scripts/studio-doctor.sh`) which
# remedy a missing receipted file is given. Derive the call sites rather than trusting a numeral
# here: grep each file for the function's name followed by a quoted argument. **Do not write that
# pattern out in a comment** — the first attempt at this sentence did, and the comment then matched
# its own instruction and inflated the answer from 2 to 3, which is the same trap this file records
# at its script-skip loop and `provenance.tsv` records in this file's row. **The address was wrong
# until 2026-08-17**: it read *"the trap `CLAUDE.md` already records"*, and a flattened probe over
# `CLAUDE.md` returns zero hits for every phrasing of it. The lesson is right and it is filed — just
# not there, and a citation that names the wrong document is how a reader concludes the lesson is
# unrecorded. This sentence also read "THREE READERS IN THIS FILE,
# AND A FOURTH IN A DIFFERENT FILE" for one commit, contradicting the enumeration on the line above
# it, in the comment whose entire job is to establish that there is one criterion.
#
# IT WAS THREE SEPARATE SPELLINGS UNTIL 2026-08-16, AND THE THIRD WAS WRONG IN BOTH DIRECTIONS.
# `studio-doctor.sh` classified a path as Codex-layer by `not under .claude/`, under a comment
# asserting it was "the criterion Step 8e uses, spelled the same way." Measured: on a project that
# had never had a Codex layer, deleting `.mcp.json` produced `re-run install.sh --client codex`,
# `1 of these are Codex-layer paths`, and `A plain install.sh will NOT restore them` — every line
# false, with `.mcp.json` printed one line above; following that remedy created `AGENTS.md`,
# `.agents/` and `.codex/` in a project that had asked for neither. The other direction:
# `.claude/state/codex-trust.tsv` IS written only by the Codex arm and is under `.claude/`, so it got
# the bare, concealing remedy this whole repair exists to remove.
#
# THE COPY IN `scripts/studio-doctor.sh` IS BYTE-IDENTICAL, AND WHAT HOLDS IT THERE IS TWO
# DIFFERENT GUARDS. install.sh is not in the payload, so the shipped script cannot source it; the
# two copies are held together by `tests/test-install-upgrade-client.sh`, which extracts both marked
# regions and compares them. If you change one, change the other in the same commit — the guard
# makes that an obligation rather than a hope. The markers are what it extracts; do not rename them.
#
# **THAT COMPARISON GUARDS THE REGION'S BYTES AND NOTHING ELSE**, and the scope matters because this
# sentence read "CANNOT DRIFT" for one commit. Measured: three shadow redefinitions of
# `codex_layer_path` placed *after* the marked region — bash takes the last one — left both regions
# byte-identical and the equality assertion **green**, in `install.sh` and in the doctor, returning
# both constant 0 and constant 1. What caught all three was arms 4 and 5's **behavioural**
# assertions (2, 2 and 5 red). So: the comparison catches a textual edit to one copy (a whitespace-
# only change reds it), its floor catches the vacuous case where both markers are renamed and the
# comparison would pass over two empty strings, and *which predicate actually runs, in which scope,
# with which argument* is guarded by those arms and by nothing here.
#
# **"THE PAIR IS ADEQUATE" WAS FALSE IN THE UNTESTED DIRECTION UNTIL 2026-08-17, AND IT WAS FALSE
# BECAUSE OF WHAT THE ARMS ASSERT RATHER THAN WHETHER THEY RUN.** Arms 1-4 all assert that Codex
# paths are *included*; not one asserted that a non-Codex path is *excluded*. Measured: a shadow
# `codex_layer_path() { return 0; }` left `tests/test-install-upgrade-client.sh` at **24/24 green**.
# The full suite did red on it elsewhere, so nothing shipped silently — but a guard that only ever
# exercises one direction of a predicate is half a guard, and the half it skips is the one where a
# too-wide criterion tells a Claude-only user to install a Codex layer they never asked for. That
# file now runs the extracted region itself against a table with members on **both** sides, with a
# floor requiring the table to keep them.
#
# AND THAT ARM READS THE REGION, NOT THE RUNNING FUNCTION, which is a real limit and is measured
# rather than asserted. Re-run 2026-08-17 against the shape that motivated all of this — a shadow
# appended AFTER the end marker, so both regions stay byte-identical:
#
#   shadow in `scripts/studio-doctor.sh`  -> test-install-upgrade-client.sh **2 red** (the
#                                            behavioural arms, which drive the doctor)
#   shadow in `install.sh`                -> test-install-upgrade-client.sh **fully GREEN**; the
#                                            full suite **38 red**, distributed
#                                            **33 / 3 / 1 / 1** across
#                                            `tests/test-install-ownership.sh`,
#                                            `tests/test-studio-doctor.sh`,
#                                            `tests/test-install-prune.sh` and
#                                            `tests/test-doctor-reverted.sh`
#
# THE FIRST VERSION OF THAT ROW HAD THE COUNT RIGHT AND THE ENUMERATION WRONG, and the mechanism is
# worth more than the correction. The harvest that produced it matched only the runner's helper
# shape, `  FAIL `, and this suite has two: a self-contained file prints `FAIL: `. It therefore saw
# 4 of the 38 and named the two files those 4 sat in — the file carrying 33 of them appeared
# nowhere. `tests/run-tests.sh` counts both shapes; a harvest that counts one reports a subset as a
# whole, with no sign that it has done so. Same class as writing FOUR and then naming five, three
# hundred lines up in the file this same pass corrected for it.
#
# So no shape ships silently, and the file that owns the criterion is still not the file that
# catches every abuse of it. Three guards, three different blind spots: the byte comparison sees a
# textual edit and no shadow; the behavioural arms see the doctor's runtime and not the installer's;
# the table arm sees the criterion's own answers and no shadow at all. Adequate is a property of the
# set, and the set's weakest member is still the comparison in this file.
#
# THE TRUST RECEIPT IS SPELLED OUT rather than written `$CODEX_TRUST_REL`, because the other copy
# has no such variable and a textual comparison is the whole mechanism.
# kinglet:codex-layer-criterion:begin
codex_layer_path() {   # $1 = project-relative path; 0 = written only by `--client codex`
  case "$1" in
    AGENTS.md|.agents/skills/*|.codex/*|.claude/state/codex-trust.tsv) return 0 ;;
    *) return 1 ;;
  esac
}
# kinglet:codex-layer-criterion:end

# ── Args ─────────────────────────────────────────────────────────────────────
PROJECT_DIR="$(pwd)"
WITH_MCP=0; WITH_INPUT_SYSTEM=0; ASSUME_YES=0; DRY_RUN=0
PROVIDER_CHOICE=""
# THE DEFAULT IS `claude`, AND THAT IS THE WHOLE COMPATIBILITY CONTRACT. Every invocation that
# worked before this flag existed must still write byte-identical bytes, so the Codex layer is
# reached only by naming it. tests/test-codex-surface.sh proves the equivalence rather than
# asserting it: the default arm and the explicit `--client claude` arm are diffed tree against tree,
# and both are checked to carry no Codex artifact at all.
CLIENT="claude"
# Tri-state on purpose: `''` means nobody has decided, which is the only state in which the run is
# allowed to ASK. Writing the user's home is the first thing this toolkit has ever done outside a
# project, so a silent default in either direction would be wrong — `--yes` takes "no", an
# interactive run is asked, and both flags below are an answer given in advance.
CODEX_TRUST=""
# Codex's own variable, honoured because Codex honours it. This is not a test hook: a user who runs
# Codex with a non-default home must have trust written to THAT home or it is written nowhere useful.
CODEX_HOME_DIR="${CODEX_HOME:-$HOME/.codex}"
# Overridable so the test suite can point at a fixture instead of the real home
# directory. install.sh reads nothing else from $HOME; this read is the first,
# it is read-only, and its absence is benign.
CLAUDE_USER_SETTINGS="${KINGLET_USER_SETTINGS:-$HOME/.claude/settings.json}"
while [ $# -gt 0 ]; do
  case "$1" in
    # Validate before shift 2: under `set -u`, `shift 2` on a trailing flag kills the script
    # before any error message can print.
    --project-dir)      [ $# -ge 2 ] || die "--project-dir requires a path"; PROJECT_DIR="$2"; shift 2 ;;
    # The VALUE is validated here too, not only its presence. `--client codxe` reaching the payload
    # section as an unrecognised string would install the Claude Code arm and say nothing about the
    # typo, which is the silent-half-install shape this whole wave exists to stop.
    --client)           [ $# -ge 2 ] || die "--client requires a value (claude or codex)"
                        case "$2" in
                          claude|codex) CLIENT="$2" ;;
                          *) die "--client must be claude or codex, not: $2" ;;
                        esac
                        shift 2 ;;
    --with-mcp)          WITH_MCP=1; shift ;;
    --with-input-system) WITH_INPUT_SYSTEM=1; shift ;;
    --codex-trust)       CODEX_TRUST=yes; shift ;;
    --no-codex-trust)    CODEX_TRUST=no; shift ;;
    --yes|-y)            ASSUME_YES=1; shift ;;
    --dry-run)           DRY_RUN=1; shift ;;
    -h|--help)           usage ;;
    *)                   die "Unknown argument: $1 (use --help)" ;;
  esac
done

# A flag that cannot do anything is a flag whose user believes it did. `--codex-trust` without
# `--client codex` has no hook config to vouch for, so it is an error rather than a no-op.
if [ "$CODEX_TRUST" = yes ] && [ "$CLIENT" != codex ]; then
  die "--codex-trust needs --client codex: trust is granted for the hook config that arm writes, and there is none without it."
fi

PROJECT_DIR="$(cd "$PROJECT_DIR" 2>/dev/null && pwd)" || die "Project directory not found"
CLAUDE_DIR="$PROJECT_DIR/.claude"
RECEIPT="$PROJECT_DIR/$RECEIPT_REL"

printf '%s\n' "${BOLD}Kinglet Pioneer ${TOOLKIT_VERSION}${NC} — installer"
info "Project: $PROJECT_DIR"
[ "$DRY_RUN" -eq 1 ] && warn "Dry run — nothing will be written."

# ── Step 1: Validate Unity project ───────────────────────────────────────────
[ -d "$PROJECT_DIR/Assets" ] || die "No Assets/ directory — this does not look like a Unity project."
[ -d "$PROJECT_DIR/ProjectSettings" ] || die "No ProjectSettings/ directory — this does not look like a Unity project."
[ -d "$SCRIPT_DIR/.claude" ] || die "Payload not found at $SCRIPT_DIR/.claude — run install.sh from the kinglet-unity repo root."
ok "Unity project detected."

# ── Step 2: Scan project ─────────────────────────────────────────────────────
UNITY_VERSION="unknown"
# awk on the file rather than `grep | head -1` — see the note in scripts/generate-claude-md.sh.
[ -f "$PROJECT_DIR/ProjectSettings/ProjectVersion.txt" ] && \
  UNITY_VERSION=$(awk '/^m_EditorVersion:/ {print $2; exit}' "$PROJECT_DIR/ProjectSettings/ProjectVersion.txt")
[ -n "$UNITY_VERSION" ] || UNITY_VERSION="unknown"
MANIFEST="$PROJECT_DIR/Packages/manifest.json"
# ONE detector, shared with scripts/generate-claude-md.sh. This block used to be two unconditional
# greps with HDRP last, so HDRP won; the generator used if/elif with URP first, so URP won. A
# project carrying both packages got HDRP here and URP in its own generated CLAUDE.md from a single
# install. See scripts/detect-pipeline.sh's header for what package presence can and cannot tell
# you — in particular that it does NOT read ProjectSettings/GraphicsSettings.asset, so none of these
# four answers is a statement about which pipeline is ACTIVE.
#
# install.sh runs BEFORE the payload is installed, so the detector is reached at $SCRIPT_DIR/scripts/
# and never at $PROJECT_DIR/.claude/scripts/. `bash "$path"`, matching how $GEN is invoked further
# down, so a lost exec bit in a checkout cannot break it.
#
# `|| die`, not a bare RENDER_PIPELINE_ID="$(...)": under `set -e` a bare assignment from a failing
# command substitution kills the installer with NO message. The status lands here at Step 2 — after
# the Unity-project gate and before anything is written or backed up — so a failure exits with the
# project untouched and no receipt to reconcile. Measured on a mutated copy, not reasoned about.
RENDER_PIPELINE_ID="$(bash "$SCRIPT_DIR/scripts/detect-pipeline.sh" "$PROJECT_DIR")" \
  || die "Render-pipeline detection failed — $SCRIPT_DIR/scripts/detect-pipeline.sh did not run."
case "$RENDER_PIPELINE_ID" in
  builtin)  RENDER_PIPELINE="Built-in" ;;
  urp)      RENDER_PIPELINE="URP" ;;
  hdrp)     RENDER_PIPELINE="HDRP" ;;
  # Named as its own state rather than silently picking a winner — which is the whole defect this
  # shared detector closes. The parenthetical is not decoration: the manifest cannot say which of
  # the two renders, and a confident "URP" here would be the wrong answer half the time.
  urp+hdrp) RENDER_PIPELINE="URP + HDRP (both packages present — active pipeline undetermined)" ;;
  # Unreachable while the detector emits the four tokens above. It reports the token instead of
  # defaulting to "Built-in", because a confident wrong answer is the failure mode this whole block
  # exists to remove.
  *)        RENDER_PIPELINE="undetermined (detector said '$RENDER_PIPELINE_ID')" ;;
esac
ok "Unity $UNITY_VERSION · $RENDER_PIPELINE"

HAS_INPUT_SYSTEM=0
if [ -f "$MANIFEST" ] && grep -q "$INPUT_SYSTEM_PKG_NAME" "$MANIFEST"; then
  HAS_INPUT_SYSTEM=1
fi
if [ "$HAS_INPUT_SYSTEM" -eq 1 ]; then
  ok "$INPUT_SYSTEM_PKG_NAME already in manifest.json."
else
  # Unconditional — unlike --with-mcp this is not an optional integration, it is what the toolkit's
  # own rules require to compile. A warning that only fires with a flag nobody knows to pass is a
  # warning nobody reads.
  warn "$INPUT_SYSTEM_PKG_NAME is missing. unity-specifics.md makes the New Input System"
  warn "non-negotiable and blocks legacy Input.* — without the package, the first script written"
  warn "under this toolkit's own rules will fail to compile."
  warn "Re-run with --with-input-system to add it, or add it to Packages/manifest.json yourself."
fi

# ── Step 3: Decide how to handle an existing .claude/ ────────────────────────
# Three cases, and the receipt is what tells them apart:
#   fresh          — no .claude/ at all
#   ours           — .claude/ + a receipt we wrote: a genuine upgrade, so we can be precise
#   foreign        — .claude/ but no receipt (a teammate's git clone, or a hand-rolled setup).
#                    We did not write it, so we do not get to assume it is ours to replace.
MODE=fresh
if [ -d "$CLAUDE_DIR" ]; then
  if [ -f "$RECEIPT" ]; then MODE=ours; else MODE=foreign; fi
fi

BACKUP_DIR=""
case "$MODE" in
  fresh)   ok "No existing .claude/ — clean install." ;;
  ours)
    PREV=$(grep -m1 '^# toolkit-version:' "$RECEIPT" 2>/dev/null | sed 's/.*: //' || echo unknown)
    info "Existing Kinglet install found (version $PREV) — upgrading to $TOOLKIT_VERSION."
    info "Files you modified will be reported and kept; untouched files are replaced."
    ;;
  foreign)
    warn "$CLAUDE_DIR exists but has no install receipt."
    warn "Kinglet did not create it, so it will not be removed or merged blindly."
    if [ "$ASSUME_YES" -eq 1 ] || [ ! -t 0 ]; then
      REPLY_CHOICE=1
      info "Non-interactive — backing up the existing .claude/ and installing fresh."
    else
      printf '\n  1) Back up %s and install fresh  (safe default)\n' ".claude/"
      printf '  2) Abort\n\n'
      read -rp "  Choose [1/2]: " REPLY_CHOICE
    fi
    case "${REPLY_CHOICE:-2}" in
      1) BACKUP_DIR="$PROJECT_DIR/.claude.backup.$(date +%Y%m%d%H%M%S)" ;;
      # THE MOST COMPLETE ABANDONMENT THIS SCRIPT HAS, AND IT EXITED 0 WITH ONE WORD OF PROSE.
      # Nothing is installed, no receipt is written, and `install.sh --yes && start_unity` proceeds
      # as though a toolkit were there. The status stays 0 — it is the user's own answer to a
      # question this run asked, not a failure — so the block is what carries it, and this is the
      # only site that emits the block anywhere but the summary. It is also the only site the guard
      # in tests/test-install-not-done.sh cannot reach: the prompt above is skipped entirely unless
      # stdin is a tty, so reaching this arm needs a pty rather than a fixture.
      *) info "Aborted."
         note_not_done "the whole installation — you chose to abort at the existing $CLAUDE_DIR prompt, so nothing was written and no receipt exists."
         print_not_done
         exit 0 ;;
    esac
    ;;
esac

# ── Step 4: Work out what we are about to write ──────────────────────────────
# Enumerated at runtime. The old installer kept hand-synced arrays of filenames in three separate
# scripts; a payload this size makes that a liability, and `find` cannot drift.
PAYLOAD_FILES=$(cd "$SCRIPT_DIR/.claude" && find . -type f ! -path './state/*' | sed 's|^\./||' | sort)
PAYLOAD_COUNT=$(printf '%s\n' "$PAYLOAD_FILES" | grep -c . || true)
info "Payload: $PAYLOAD_COUNT files"

# Every .claude path this run will own, in receipt form. Built here rather than derived twice,
# because the dry run and the real run must answer the same question: what belongs afterwards?
# Keep this in step with the two write loops below (the payload loop and the `for group in scripts`
# loop) — a path written but missing here would be deleted as an orphan the run after it appears.
# There is one group and it is `scripts`. This line read "the scripts/tests groups" until 2026-08-12,
# naming a tests/ write that has never existed — the same defect as the dry-run summary's old
# "scripts/ and tests/ into .claude/" line, which was fixed while this one was left standing.
NEW_PATHS=$(
  printf '%s\n' "$PAYLOAD_FILES" | sed 's|^|.claude/|'
  # shellcheck disable=SC2043
  # One group today, and deliberately a list: see the paragraph above, which records the round where
  # this named a `tests` group that has never existed.
  for group in scripts; do
    [ -d "$SCRIPT_DIR/$group" ] || continue
    for f in "$SCRIPT_DIR/$group"/*.sh; do
      [ -f "$f" ] || continue
      b=$(basename "$f")
      [ "$b" = "check-provenance.sh" ] && continue
      [ "$b" = "codex-probe.sh" ] && continue
      printf '.claude/%s/%s\n' "$group" "$b"
    done
  done
)
NEW_PATHS=$(printf '%s\n' "$NEW_PATHS" | sort -u)

# The dry run reported the payload as a file count and the scripts group as a bare name — two lines
# in two different units, so a reader could not add them up and get the number of files this run
# writes. Counted off NEW_PATHS rather than re-walking scripts/, so it cannot disagree with the
# enumeration the real run and the receipt are both built from.
SCRIPTS_COUNT=$(printf '%s\n' "$NEW_PATHS" | grep -c '^\.claude/scripts/' || true)

# A missing file hashes to the empty string, and the guard lives HERE rather than at each call site.
#
# The old body was `sha256sum "$1" 2>/dev/null | cut -d' ' -f1`, which is safe only for as long as
# every caller happens to check existence first. They all do today — owned_by_installer returns
# early, the upgrade scan `continue`s, and both write loops hash a file they just wrote or just
# proved present — so this changes no behaviour now. It is the asymmetry that is the defect: the
# helper's contract was "the caller has already checked", enforced nowhere.
#
# Two different failures were one edit away. Under `set -euo pipefail` sha256sum exits 1 on a
# missing path, pipefail promotes that through the `| cut`, and at an ASSIGNMENT site set -e kills
# the installer with no message. At the four receipt-row sites the substitution sits inside a printf
# argument, where set -e does not reach, so the same miss instead writes a row with an EMPTY
# checksum — a receipt that uninstall.sh will silently decline to act on, which is worse. Measured
# in tests/test-install-ownership.sh, where the identical helper took the whole test file down
# mid-state and the assertions after it read as absent rather than red.
sha_of() {
  [ -f "$1" ] || return 0
  sha256sum "$1" | cut -d' ' -f1
}

# ── Ownership, not authorship ────────────────────────────────────────────────
# A receipt row says "this file is ours to remove", not "this run wrote it". Those were the same
# sentence while the project-root rows were written inside their create branches, and they part
# company on the second install: the branch is skipped, $RECEIPT_TMP is rebuilt from scratch, and
# the rebuilt receipt disowns a file the installer put there. uninstall.sh — which removes only
# receipt-listed paths, deliberately, because a previous version deleted by filename — then leaves
# it behind forever. Two installs, the same files, a different ownership record, and the second
# record is the wrong one.
#
# THE TEST MUST FAIL CLOSED. Claiming a file we do not own means uninstall.sh deletes the user's
# work, which is the whole reason the uninstaller is receipt-driven. So ownership is proved, never
# assumed, by one of two checksum comparisons, and a file that satisfies neither gets no row:
#
#   1. it is byte-for-byte the copy this toolkit ships, or
#   2. a previous run recorded it as `toolkit` AND it still carries that run's checksum.
#
# The second half of (2) is what makes "the user edits a file we installed" come out right. The row
# is there and says `toolkit`; the bytes have moved; we do not renew the claim. Reading presence in
# the old receipt alone would renew it, and uninstall.sh would delete an edited file.
#
# No `user-modified` row is written for these two, and that is a decision rather than an omission.
#
# It was once forced by a defect elsewhere: uninstall.sh's classifier compared the recorded checksum
# and never read the origin column, so a `user-modified` row — which records the file AS EDITED —
# matched on sha and was deleted by a plain `uninstall.sh --yes`. Measured 2026-08-12 on
# .claude/rules/pc-console.md, and FIXED the same day: the classifier now branches on origin first,
# and tests/test-install-ownership.sh's state G holds all three directions of it.
#
# The decision survives the fix, for a reason that was always the better one. A `user-modified` row
# is still a claim of ownership, and `--purge` acts on every claim. State C's MCP-SETUP.md — one the
# user wrote before any install ever ran — is not ours to purge, and nothing at this call site can
# tell that file apart from one of ours the user rewrote. No row, no claim.
#
# $RECEIPT still holds the PREVIOUS run's receipt at every call site below. Four statements could
# have changed that and none does: Step 9 is the only writer, the payload enumeration excludes
# state/, the orphan sweep skips .claude/state/*, and `mv "$CLAUDE_DIR" "$BACKUP_DIR"` in Step 5
# moves the whole directory away — but only in `foreign` mode, which is DEFINED by the receipt
# being absent, so the `[ -f "$RECEIPT" ]` guard below is already false there and fails closed.
owned_by_installer() {
  # $1 project-relative path; $2 the toolkit's copy of it ('' when there is none on disk).
  local rel="$1" ref="${2:-}" abs have
  abs="$PROJECT_DIR/$rel"
  [ -f "$abs" ] || return 1
  have=$(sha_of "$abs")
  if [ -n "$ref" ] && [ -f "$ref" ] && [ "$have" = "$(sha_of "$ref")" ]; then
    return 0
  fi
  [ -f "$RECEIPT" ] || return 1
  # THE ORIGIN COLUMN IS TRIMMED BEFORE IT IS COMPARED, and the trim is not cosmetic. `$4 ==
  # "toolkit"` is byte equality, so a row carrying one trailing space — or a CRLF line ending, which
  # puts a \r in field 4 of the last column — is not `toolkit` and the file is not re-claimed. It is
  # then never claimed again by any later run either, because every run reads the receipt it wrote
  # last time: uninstall.sh removes only listed paths, so the file is permanent debris. That costs a
  # root file its ownership FOREVER on a byte a user cannot see.
  #
  # THE OTHER DIRECTION IS THE ONE THAT MUST NOT MOVE, and trimming is what keeps it still. A
  # mangled `user-modified ` trims to `user-modified`, which is still not `toolkit`, so it is still
  # not claimed and uninstall.sh still leaves the user's file alone — the direction G.5 in
  # tests/test-install-ownership.sh holds for the classifier, held here for the writer. Anything
  # that is neither value after trimming — an empty column, a fifth value, a truncated row — is
  # still not claimed. Unknown provenance is not ours, and the cost of that is a file left on disk,
  # which the user can delete; the cost of the other answer is a file deleted, which they cannot
  # undelete. States N and N2 assert both directions across an upgrade, which is the only shape
  # where this awk is the whole decision (the reference-copy arm above answers otherwise).
  #
  # WHICH READERS OF THIS COLUMN TRIM, AND WHICH DO NOT. There are four, and the sentence above is
  # about ONE of them, so it is stated here for the column rather than left to be read off whichever
  # reader you happened to open. This paragraph shipped for one round saying "a CRLF line ending" is
  # handled without saying handled BY WHOM, and the next three tasks to open this file would have
  # read it as a property of the receipt format:
  #
  #   install.sh, this awk                       — TRIMS. Deciding whether to re-claim a file.
  #   install.sh, the MODIFIED_FILES loop below  — TRIMS. Deciding whether to overwrite the user's
  #                                                edit. This is the reader where being wrong costs
  #                                                work that cannot be recovered, and it was the
  #                                                untrimmed one until 2026-08-14: `user-modified `,
  #                                                ` user-modified` and a CRLF receipt each silently
  #                                                destroyed the edit and rewrote the row `toolkit`.
  #   uninstall.sh's classifier                  — DOES NOT TRIM. It is fail-closed by a different
  #                                                mechanism: a `case` whose `*)` keeps the file. So
  #                                                a mangled `user-modified` is safe there, but a
  #                                                mangled `toolkit ` on an UNEDITED file is
  #                                                classified as yours and never removed — this
  #                                                defect's mirror image, unfixed, on that side.
  #   scripts/studio-doctor.sh                   — DOES NOT TRIM. Same `case` shape; reports an
  #                                                unreadable origin on its own line rather than
  #                                                counting it verified. Diagnostic only, writes
  #                                                nothing, so it cannot destroy anything. Its
  #                                                `user-modified` arm now makes the same
  #                                                reference-copy comparison the MODIFIED_FILES loop
  #                                                below does, so the two cannot disagree about
  #                                                whether a file has been put back — but only when
  #                                                --toolkit-dir gives it a checkout to compare
  #                                                against, which an installed project has not got.
  #
  # Keep this list in step with the file if you add a reader, and do not shorten it to "the origin
  # column is trimmed" — that sentence is true of two readers and false of four.
  awk -F'\t' -v want="$rel" -v have="$have" '
    $1 == want && $2 == have {
      origin = $4
      sub(/^[[:space:]]+/, "", origin)
      sub(/[[:space:]]+$/, "", origin)
      if (origin == "toolkit") { found = 1 }
    }
    END { exit !found }' "$RECEIPT"
}

# On upgrade, find files the user edited so we can leave them alone.
#
# THREE LISTS, AND THE SPLIT IS NOT COSMETIC. `MODIFIED_FILES` is the UNION and it is what
# `is_modified` reads, so every path this run declines to overwrite has to be in it. `EDITED_FILES`
# and `UNREADABLE_ORIGINS` partition that union by WHY, and they are what the run PRINTS.
#
# One list for both was wrong in the direction that matters: an unedited payload file whose receipt
# row carries an unreadable origin was reported under `installed file(s) have local edits — keeping
# yours` and named again two lines later under the unreadable block. Printed twice, counted once in
# a number describing two different situations, and `have local edits` is simply false about a file
# nobody edited. Measured 2026-08-14 on a --variant urp fixture with an unedited
# .claude/rules/pc-console.md and its origin column mangled to `toolkit<TAB>deadbeef`.
#
# The comment below this one already argued that "kept-because-yours and kept-because-unreadable are
# different futures, and a single count would describe neither" — and then the count described both.
#
# A FOURTH LIST, AND IT IS A SUBTRACTION FROM THE UNION RATHER THAN A PARTITION OF IT.
# `RECLAIMED_FILES` names files whose row says `user-modified` and whose bytes are now byte-for-byte
# the copy this toolkit ships — the user put the file back. They are deliberately NOT in
# MODIFIED_FILES: the whole point is that the payload loop writes them again and records them
# `toolkit`, so the sticky flag stops surviving its own reason. See the arm below.
MODIFIED_FILES=""
EDITED_FILES=""
UNREADABLE_ORIGINS=""
RECLAIMED_FILES=""
if [ "$MODE" = ours ]; then
  while IFS=$'\t' read -r rel recorded _mode origin; do
    case "$rel" in ''|\#*) continue ;; esac
    [ -f "$PROJECT_DIR/$rel" ] || continue
    # `user-modified` is sticky. When a previous run kept your edit, it recorded the file as it then
    # stood — so on the next run the checksum matches the receipt and a sha-only test concludes the
    # file is untouched and overwrites it. Your edit survived exactly one upgrade and then vanished,
    # silently. Measured twice on the same file in one day. The origin column was already written
    # for this; it was just never read.
    #
    # TRIMMED, AND THIS IS THE READER WHERE GETTING IT WRONG COSTS THE USER'S WORK. `[ "$origin" =
    # user-modified ]` is byte equality, and everything that reaches it has already survived a `read`
    # that strips only IFS whitespace — which here is the TAB, not the space. So a receipt whose
    # origin column carries one trailing space, or one leading space, or a `\r` from a Windows editor
    # saving the file with CRLF endings, is not `user-modified` to that test. Measured 2026-08-14 on
    # a --variant urp fixture, install → edit .claude/rules/pc-console.md → install: with any of
    # those three bytes present the edit is GONE, no `keeping yours` line is printed, and the row is
    # rewritten as a clean `toolkit`. The one shape that already survived is a LEADING TAB, and it
    # survived by accident rather than by care — `read` strips it as IFS whitespace before this test
    # ever sees it. All four are asserted in tests/test-install-ownership.sh's state P.
    #
    # THE TRIM IS NARROW ON PURPOSE: surrounding whitespace only, then exact equality. It must not
    # become a prefix or substring match. A row carrying a genuine fifth column reaches this loop as
    # `user-modified<TAB>deadbeef` — the tab is INTERNAL, so `read` does not strip it — and that is a
    # row whose provenance we cannot read, not a `user-modified` row with decoration. State P4
    # asserts it takes the `*)` branch below and not this one.
    #
    # Pure parameter expansion rather than a `sed`/`tr` per row: this loop runs once per receipt row,
    # and bash 3.2 has to parse it, so no `${x//…}` with a class and no `$'…'` inside the pattern.
    origin_clean="${origin#"${origin%%[![:space:]]*}"}"
    origin_clean="${origin_clean%"${origin_clean##*[![:space:]]}"}"
    # A `case` with an explicit catch-all, which is the grammar uninstall.sh's classifier and
    # scripts/studio-doctor.sh both already use. The if/else this replaces let anything unrecognised
    # fall THROUGH to the sha test, and on a mangled row the sha still matches — the row records the
    # edited file — so the fall-through concluded "untouched" and the payload loop overwrote it. A
    # file whose provenance we cannot read is not ours to overwrite, so it is kept and SAID ALOUD on
    # its own line: kept-because-yours and kept-because-unreadable are different futures, and a
    # single count would describe neither.
    case "$origin_clean" in
      user-modified)
        # STICKY UNTIL THE BYTES COME BACK — AND THE COMPARISON IS AGAINST THE TOOLKIT'S COPY, NOT
        # THE RECORDED SHA. Once a run keeps your edit it records the file AS EDITED, and the arm
        # above reads that row on every later run. Nothing ever took the flag off, so reverting the
        # file — `git checkout`, an undo, pasting the shipped text back — left it permanently yours:
        # measured 2026-08-14 on a --variant urp fixture, install → edit → install → revert to the
        # toolkit's exact bytes → install, and the run still printed `1 installed file(s) have local
        # edits — keeping yours` about a file with no local edits, rewriting the row `user-modified`
        # with the TOOLKIT'S OWN checksum in it. The cost is not the wrong sentence: this version's
        # copy of that file never lands again, so every later fix to it silently skips the project.
        # A second fixture that never touched the file received the bump in the same run.
        #
        # THIS IS NOT THE COMPARISON THAT FAILED IN c2d27f1f. That one tested the file against its
        # RECORDED sha, which for a `user-modified` row is the sha of the edited file — so it matched
        # while the edit was still in place, concluded "untouched", and the payload loop destroyed
        # the edit on the next run. An EDITED file never equals the toolkit's bytes, so the test here
        # cannot answer yes while the work is still there. The two directions are asserted together
        # in tests/test-install-ownership.sh's states R…R3, and the second is the regression check:
        # edit, then three consecutive installs, and the edit survives all three.
        #
        # WHICH FILES HAVE A REFERENCE COPY, AND WHY THE MAPPING IS TWO ARMS AND NOT ONE. Step 5's
        # payload loop takes `.claude/<rel>` from `$SCRIPT_DIR/.claude/<rel>`; the scripts loop takes
        # `.claude/scripts/<name>` from the repo-root `$SCRIPT_DIR/scripts/<name>`, because there is
        # no `.claude/scripts/` in this repository at all. Collapsing them to one arm makes every
        # scripts row look referenceless and the flag stays stuck there for a reason that reads as
        # deliberate.
        #
        # EVERYTHING ELSE KEEPS THE FLAG, and that is the fail-closed direction. A row with no
        # reference copy on disk — a retired surface this payload no longer ships, or a project-root
        # path — cannot be proved reverted, so it is not.
        #
        # THERE IS EXACTLY ONE PROJECT-ROOT WRITER OF A `user-modified` ROW, AND IT ARRIVED
        # 2026-08-17. This paragraph read *"no writer in this file emits a `user-modified` row for a
        # project-root path … so the only way one reaches this arm is a hand-edited receipt"*, and
        # Step 8d.1 now does emit one, for `AGENTS.md`, on every run that keeps or refreshes a Codex
        # entry document a previous run wrote and that still carries our marker pair. That row reaches
        # this arm on the next install and is correctly kept: `AGENTS.md` is generated per project, so
        # it has no reference copy here and no `case` arm below matches it — which is the right answer
        # rather than a gap, because there is nothing to compare it against and "put back to the
        # shipped bytes" is not a state this file has. The flag is therefore permanent once set.
        #
        # `AGENTS.md` AND `CLAUDE.md` SHARE ONE HALF OF THIS AND NOT THE OTHER, AND THE SENTENCE HERE
        # CLAIMED BOTH FOR A DAY. It read *"that is the same contract `CLAUDE.md` has had all along"*.
        # What is shared: after the user edits it, only the marked region is maintained. What is not:
        # `CLAUDE.md` has NO receipt row of any kind — it is never in `MODIFIED_FILES`, never listed
        # under `keeping yours`, and `uninstall.sh --purge` has never reached it. Measured on a
        # fixture, and `tests/test-install-ownership.sh`'s S…S4 header says the same thing from the
        # other side: *"the one project-root file that has no receipt row at all: CLAUDE.md. It is
        # never claimed, never removed by uninstall.sh."* So `AGENTS.md` now carries an ownership
        # claim its sibling does not, which is the price of the freeze not being silent — the row is
        # the mechanism that makes the doctor and the uninstaller able to see it at all.
        #
        # The other project-root paths are unchanged — .mcp.json, MCP-SETUP.md, CLAUDE.md.generated,
        # .gitignore and the manifest backup are all still written `toolkit` or not at all.
        # MCP-SETUP.md does ship a static copy at $SCRIPT_DIR/MCP-SETUP.md and is still not given a
        # reference here: adding one would be a behaviour with no producer.
        ref=''
        case "$rel" in
          .claude/scripts/*) ref="$SCRIPT_DIR/scripts/${rel#.claude/scripts/}" ;;
          .claude/*)         ref="$SCRIPT_DIR/.claude/${rel#.claude/}" ;;
        esac
        if [ -n "$ref" ] && [ -f "$ref" ] \
           && [ "$(sha_of "$PROJECT_DIR/$rel")" = "$(sha_of "$ref")" ]; then
          RECLAIMED_FILES="${RECLAIMED_FILES}${rel}"$'\n'
          continue
        fi
        MODIFIED_FILES="${MODIFIED_FILES}${rel}"$'\n'
        EDITED_FILES="${EDITED_FILES}${rel}"$'\n'
        continue
        ;;
      toolkit)
        ;;
      *)
        UNREADABLE_ORIGINS="${UNREADABLE_ORIGINS}${rel}"$'\n'
        MODIFIED_FILES="${MODIFIED_FILES}${rel}"$'\n'
        continue
        ;;
    esac
    actual=$(sha_of "$PROJECT_DIR/$rel")
    if [ "$actual" != "$recorded" ]; then
      MODIFIED_FILES="${MODIFIED_FILES}${rel}"$'\n'
      EDITED_FILES="${EDITED_FILES}${rel}"$'\n'
    fi
  done < <(grep -v '^#' "$RECEIPT" 2>/dev/null | tail -n +2 || true)
  # EDITED_FILES, not MODIFIED_FILES — see the three-list note above. `have local edits` has to be
  # true of every path under it.
  MOD_COUNT=$(printf '%s' "$EDITED_FILES" | grep -c . || true)
  if [ "$MOD_COUNT" -gt 0 ]; then
    warn "$MOD_COUNT installed file(s) have local edits — keeping yours:"
    printf '%s' "$EDITED_FILES" | while IFS= read -r m; do [ -n "$m" ] && printf '       %s\n' "$m"; done
  fi
  # SAID ALOUD, because the previous run said the opposite about the same file. A user who has seen
  # `keeping yours: .claude/rules/pc-console.md` on every install since they edited it, and who then
  # put the file back, is owed the sentence that closes that thread — otherwise the line simply stops
  # appearing and the kept-count silently drops by one. `info`, not `warn`: nothing here needs
  # attention and nothing was abandoned, so this is deliberately NOT a `note_not_done` entry either
  # (see that block's "what does not belong here").
  RECLAIMED_COUNT=$(printf '%s' "$RECLAIMED_FILES" | grep -c . || true)
  if [ "$RECLAIMED_COUNT" -gt 0 ]; then
    info "$RECLAIMED_COUNT file(s) you had edited are back to this version's bytes — no longer kept as yours:"
    printf '%s' "$RECLAIMED_FILES" | while IFS= read -r r; do
      if [ -n "$r" ]; then printf '       %s\n' "$r"; fi
    done
    info "This version's copies land again, and future updates to them will reach this project."
  fi
  # `if`, not `[ -n "$u" ] && printf`, inside the loop body: a false test as a loop body's last
  # command is a `set -e` kill, and this block is new enough not to inherit the older idiom's luck.
  UNREADABLE_COUNT=$(printf '%s' "$UNREADABLE_ORIGINS" | grep -c . || true)
  if [ "$UNREADABLE_COUNT" -gt 0 ]; then
    warn "$UNREADABLE_COUNT receipt row(s) carry an origin this installer cannot read — keeping those files:"
    printf '%s' "$UNREADABLE_ORIGINS" | while IFS= read -r u; do
      if [ -n "$u" ]; then printf '       %s\n' "$u"; fi
    done
    # THIS SENTENCE USED TO END `so they are neither replaced nor claimed`, AND THE SECOND HALF WAS
    # FALSE. The file is kept, which puts it in MODIFIED_FILES, which sends the payload loop down its
    # `user-modified` arm — and that arm writes a receipt row. This file's own header says what such a
    # row means: "a `user-modified` row is still a claim of ownership, and `--purge` acts on every
    # claim." Measured 2026-08-14: after the run printed `nor claimed`, `uninstall.sh --yes --purge`
    # REMOVED the file. A sentence that tells the user a file is unclaimed, immediately before
    # claiming it, is the false-reassurance half of a defect rather than a report of one.
    #
    # WRITING NO ROW AT ALL WAS THE OTHER CANDIDATE AND IT IS MEASURABLY WORSE. A kept file with no
    # row is invisible to the NEXT run's loop above — nothing puts it in MODIFIED_FILES, so the
    # payload loop overwrites it. Measured on the same fixture by deleting the row and re-running:
    # the file was replaced, with no `keeping yours` line and no unreadable-origin line. That is the
    # data-loss path this task closed, delayed by one run and made silent. So the row stays and the
    # sentence changes.
    #
    # THE TEST THE WORDING HAS TO PASS is whether a reader who has just read it predicts what
    # `--purge` does. Both halves are therefore stated, and both are asserted in state Q.
    warn "Their provenance cannot be established, so they are kept rather than replaced — and"
    warn "recorded as yours. Plain 'uninstall.sh' will leave them; 'uninstall.sh --purge' removes them."
    # IN THE BLOCK, WHERE `keeping yours` DELIBERATELY IS NOT. The distinction is who decided: an
    # edited file is kept because the user edited it, and the file on disk is the one they want. Here
    # nobody decided anything — the origin column is unreadable — so what is on disk may be this
    # version's copy or a stale one, and the run cannot say which. That is the installer failing to
    # deliver a payload file, not honouring a choice.
    note_not_done "$UNREADABLE_COUNT installed file(s) listed above were NOT replaced with this version's copies — their receipt origin cannot be read, so they were kept and recorded as yours. Fix the origin column in $RECEIPT_REL, or delete those rows and re-install, to get this version's copies."
  fi
fi

is_modified() { grep -qxF -- "$1" <<< "$MODIFIED_FILES"; }

# Surfaces the previous install owns and this payload no longer contains.
#
# The installer used to only ever add. The 2026-08-03 surface cut removed 74 files, and installing
# over an older install left every one of them on disk and selectable — 114 orphans against a real
# project — so the cut was invisible in the only place it matters. An upgrade that leaves a deleted
# agent reachable is worse than no upgrade: the model still sees it.
#
# Anything the user edited is never removed. A file whose checksum drifted is theirs, whatever the
# payload now says, and deleting it is the failure mode this installer just finished fixing on the
# other side.
ORPHANS=""; ORPHANS_KEPT=""
if [ "$MODE" = ours ]; then
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    case "$rel" in .claude/state/*) continue ;; esac
    [ -e "$PROJECT_DIR/$rel" ] || continue
    if is_modified "$rel"; then
      ORPHANS_KEPT="${ORPHANS_KEPT}${rel}"$'\n'
    else
      ORPHANS="${ORPHANS}${rel}"$'\n'
    fi
  done < <(comm -23 \
      <(grep -v '^#' "$RECEIPT" 2>/dev/null | tail -n +2 | cut -f1 | grep '^\.claude/' | sort -u) \
      <(printf '%s\n' "$NEW_PATHS"))
fi
ORPHAN_COUNT=$(printf '%s' "$ORPHANS" | grep -c . || true)
ORPHAN_KEPT_COUNT=$(printf '%s' "$ORPHANS_KEPT" | grep -c . || true)

# ── Step 3b: The decisions the dry run and the real run must not compute twice ───────────────────
#
# Everything below is ANNOUNCED by the `Would install:` block a few lines down and ACTED ON by
# Steps 7 and 8, hundreds of lines later. It lives here, above both, for the reason this block has
# already paid for twice — once on the CLAUDE.md branch, once on MCP-SETUP.md: an announcement
# computed from a COPY of the write's condition is a second definition of that condition, and a
# second definition drifts. Call the predicate; never restate it.

# ── The marker-pair decision, for BOTH generated entry documents ─────────────
# IT ANSWERS FOR TWO FILES, NOT ONE, AND THE SECOND ARRIVED ON 2026-08-17. `CLAUDE.md` and the
# `--client codex` arm's `AGENTS.md` are emitted by the same generator, from the same template, and
# both carry the same `kinglet:generated` pair — install 1 of either writes a file with exactly one
# begin and one end. Until this date only CLAUDE.md's branch ever LOOKED at them, so an `AGENTS.md`
# the user had edited was frozen for good: no reinstall, upgrade or fix could update it again. These
# three functions were named `claude_md_marker_*` and are named for the region now, because a
# function whose name states one file while two files call it is a false sentence in the tree, and
# this repository has already paid for several of those.
#
# WHICH CLAUDE.md BRANCH A RUN TAKES USED TO BE `grep -q kinglet:generated:begin`, IN TWO PLACES —
# the dry run's announcement and Step 6's write — and both asked only whether the OPENING marker
# exists. A file carrying a begin and no end satisfied that test, so the refresh arm ran its awk
# merge against a region it could not close.
#
# What that costs is not a warning. The merge sets `skip` at the begin line and clears it ONLY at
# the end line, so with no end line every remaining line of the user's file is dropped — and the
# result is begin-only, so the NEXT run amputates the (now shorter) file again and reports success
# again. Measured on a urp fixture at this commit: 122 lines / 4839 bytes -> 80 lines / 2746 bytes,
# destroying five of the user's own sections, and byte-identical over runs 2, 3 and 4. The run
# printed `ok Refreshed the generated section of CLAUDE.md (your prose untouched)`, which is the
# half a user actually reads.
#
# The end-before-begin file is the same defect with a different silhouette and it is the reason the
# fix is not "clear skip at EOF": there the merge clears `skip` at the end marker, prints the OLD
# region as if it were prose, then sets `skip` at the begin marker and drops everything after it.
# Measured on the same fixture: 123 lines / 4870 bytes -> 134 lines / 4385 bytes. It GREW by eleven
# lines while losing four of the user's sections, which is why nothing here measures damage by size.
#
# SO THE PREDICATE ANSWERS FOR THE PAIR, NOT FOR THE OPENING MARKER, and a pair this function cannot
# certify is one the installer declines to merge — the same posture it already takes toward a file
# it does not own. Repair is deliberately not attempted: a file whose structure we cannot parse is a
# file whose region boundary we would be guessing at, and the guess is applied to the user's prose.
#
# EXACTLY ONE OF EACH, IN ORDER. Two begin markers is not a harmless duplicate: the merge dumps the
# facts block at each one and drops everything between the second and the next end. Fail closed.
#
# `awk` over the file, not `grep | ...`: nothing here may pipe into a reader that can exit early.
#
# IT ALWAYS EXITS 0 AND ALWAYS PRINTS A TOKEN. This comment claimed for one round that without the
# `-r` guard an unreadable CLAUDE.md would kill the run at `X="$(marked_region_state …)"`, after
# the payload had landed, leaving the trap to write an INCOMPLETE receipt. THAT IS FALSE, AND IT WAS
# FALSE FOR TWO INDEPENDENT REASONS, BOTH MEASURED against a `chmod 000` CLAUDE.md with the guard and
# the `|| out=""` fallback both removed: rc **0**, the run completed, the receipt was written, and it
# still declined — via the generic `do not form exactly one begin/end pair` message, because the
# empty token satisfies the `!= none` test at the call site.
#
#   * `printf` is this function's LAST command, so the function's status is printf's, whatever awk
#     did before it; and
#   * bash CLEARS `-e` in the subshell it spawns for a command substitution unless `inherit_errexit`
#     is on, so the failing assignment inside this function would not have ended the function even
#     if printf were not last. Derive that this file sets no such option with the comments EXCLUDED —
#     `awk '!/^[[:space:]]*#/ && /shopt/' install.sh` — because the naive `grep -n shopt` now matches
#     the two lines you are reading and answers its own question wrongly.
#
# THE DEATH IS REAL IN THREE SHAPES, and they are worth naming because any of them could arrive by an
# edit that looks like tidying. The first two were measured, rc=2, against the same chmod 000
# fixture: a rewrite that makes the failing ASSIGNMENT the function's last command (drop the trailing
# `printf` and let `out=` fall out of the end), and this exact printf-last shape under
# `shopt -s inherit_errexit`.
#
# THE THIRD IS `set -u`, AND IT NEEDS NEITHER OF THOSE PRECONDITIONS. Call this function with no
# argument — a caller that drops the path, or gains a default that is never passed — and `[ -f "$1" ]`
# is an unbound-variable error. That is a fatal shell error, not an errexit death, so the
# `-e`-clearing that defuses the other two does not touch it: the substitution subshell exits 1, and
# the call site is an assignment in the main shell under `set -e`, so the run ends. Measured
# 2026-08-14 on this exact function body: with `set -euo pipefail`, `$1: unbound variable`, rc=1,
# before the file is ever opened; with `-u` off, the same call returns `absent` and rc=0. This header
# said "exactly two shapes" until then — a closed list, in a comment about a function whose whole
# subject is a predicate that must not guess.
#
# So the guard stays for what it actually buys, which is not survival: the correct `it exists but
# could not be read` / `Make CLAUDE.md readable` pair instead of a marker diagnosis about a file
# nobody could open, and immunity to the second shape above if this file ever gains inherit_errexit.
# `unreadable` is a real state, not a fallback: it declines, like every other state this function
# cannot certify.
marked_region_state() {
  local out
  [ -f "$1" ] || { printf 'absent\n'; return 0; }
  [ -r "$1" ] || { printf 'unreadable\n'; return 0; }
  out="$(awk '
    /kinglet:generated:begin/ { b++; if (bl == 0) bl = NR }
    /kinglet:generated:end/   { e++; if (el == 0) el = NR }
    END {
      if (b + 0 == 0 && e + 0 == 0)                    { print "none" }
      else if (b + 0 == 1 && e + 0 == 1 && bl < el)    { print "wellformed" }
      else if (e + 0 == 0)                             { print "malformed-no-end" }
      else if (b + 0 == 0)                             { print "malformed-no-begin" }
      else if (b + 0 == 1 && e + 0 == 1 && bl == el)   { print "malformed-same-line" }
      else if (b + 0 == 1 && e + 0 == 1)               { print "malformed-order" }
      else                                             { print "malformed-count" }
    }
  ' "$1" 2>/dev/null)" || out=""
  [ -n "$out" ] || out="unreadable"
  printf '%s\n' "$out"
}

# The user-facing half, kept beside the predicate so a new state cannot get a token and no sentence.
# One clause, no trailing punctuation: all three call sites embed it mid-sentence.
#
# `malformed-same-line` HAS ITS OWN TOKEN BECAUSE IT HAD THE WRONG SENTENCE. One line carrying both
# markers fails `bl < el` and used to fall through to `malformed-order`, which told the user their
# end marker came before their begin marker — a statement about ordering that is not true of a single
# line, on a file where the remedy sentence was nevertheless right. The action was never in question;
# the diagnosis was, and a diagnosis a reader can check against their own file is the point of having
# one at all.
marked_region_problem() {
  case "$1" in
    malformed-no-end)     printf 'its kinglet:generated:begin marker has no closing :end marker' ;;
    malformed-no-begin)   printf 'its kinglet:generated:end marker has no opening :begin marker' ;;
    malformed-same-line)  printf 'its kinglet:generated:begin and :end markers are on the same line' ;;
    malformed-order)      printf 'its kinglet:generated:end marker comes before its :begin marker' ;;
    unreadable)           printf 'it exists but could not be read' ;;
    *)                    printf 'its kinglet:generated markers do not form exactly one begin/end pair' ;;
  esac
}

# And the remedy, which is NOT the same sentence for every declined state — "repair the marker pair"
# is wrong advice for a file the installer could not open. A whole sentence, naming the file: the
# `Next steps` summary embeds it with no context around it.
#
# THREE ARGUMENTS, ALL REQUIRED, AND THE THIRD IS NOT DECORATION. The file name was a literal here
# until AGENTS.md became a caller; the re-run command is separate from it because the two files are
# restored by different invocations. `AGENTS.md` is written only by `--client codex`, and Task 12
# measured what a bare `re-run install.sh` does to a reader who follows it on a Codex-layer path: the
# default client does not write that file, so the remedy silently fails to remedy anything. This is
# the same sentence `scripts/studio-doctor.sh` has to say for the same reason, and
# tests/test-install-upgrade-client.sh arm 4 already guards that spelling on the doctor's side.
#
# No `${2:-CLAUDE.md}` default: a default here would let a new call site forget the argument and get
# a remedy naming a file it is not about, which is precisely the failure the parameter exists to end.
marked_region_remedy() {
  case "$1" in
    unreadable) printf 'Make %s readable and re-run %s.' "$2" "$3" ;;
    *)          printf 'Repair the kinglet:generated marker pair in %s — one :begin line, one :end line after it — then re-run %s.' "$2" "$3" ;;
  esac
}

# ── The merge itself, and it is ONE implementation for both files ────────────
# Replace everything between the target's markers with $2's contents, in place, leaving every byte
# outside the pair alone. Callers must have proved the pair `wellformed` first — the awk sets `skip`
# at the begin line and clears it only at the end line, so against an unbounded pair it deletes the
# rest of the file. That is not a hypothetical: it is the measured defect recorded above
# `marked_region_state`, and the whole reason that predicate exists.
#
# A SECOND COPY OF THIS AWK IS THE FAILURE MODE THIS FUNCTION EXISTS TO PREVENT. Task 12 found two
# spellings of one criterion in two files, one of which was wrong in both directions, and had to hold
# them together with a byte-comparison guard because `install.sh` is not in the payload and the
# shipped script cannot source it. Here both callers are in THIS file, so the drift is closable
# outright rather than guarded: one function, two call sites, no copies, nothing to compare.
#
# A READ-ONLY TARGET IS REFUSED BEFORE ANYTHING IS WRITTEN, AND THAT IS THE FIRST THING THIS FUNCTION
# DOES. `mv` onto a file with no write bit ASKS — `mv: replace 'x', overriding mode 0444 (r--r--r--)?`
# — whenever stdin is a tty, and `--yes` is this installer's own flag and does not reach it. Declined
# (or EOF), `mv` exits **1** and leaves the file alone. The first version of this function ignored
# that status, and because BOTH call sites invoke it inside an `if` CONDITION — where `set -e` is
# suspended for everything the condition runs, including inside the function — it fell through to the
# `chmod` and `return 0`. Measured 2026-08-17 under a pty on a urp fixture with `AGENTS.md` at 0444:
# `ok Refreshed the generated section of AGENTS.md (your prose untouched)`, Next step 2 repeating it,
# a `user-modified` receipt row carrying the sha of the UNREFRESHED file, `INSTALL_RC=0`, and the file
# byte-identical. The same shape on `CLAUDE.md`.
#
# IT WAS A REGRESSION, NOT AN INHERITED DEFECT. Step 6's pre-2026-08-17 merge was
# `awk … > "$TMP.merged" && mv "$TMP.merged" "$CLAUDE_MD"` as a BARE command, so a declined `mv`
# propagated and `set -e` ended the run with `This install did not finish (exit 1)`. A loud abort was
# replaced by a silent false success — the one trade this repository rates as worse than the failure.
#
# 0444 IS NOT AN EXOTIC INPUT HERE. Perforce keeps every unopened file read-only, so on a P4-managed
# Unity project both entry documents are 0444 whenever they are not checked out.
#
# SO THE REFUSAL COMES FIRST AND `mv` IS STILL CHECKED, because they answer different questions. The
# `-w` test is about the file the user has to act on and lets the caller print a remedy naming it; the
# `mv` status is the backstop for everything else that can go wrong at rename time — a read-only
# parent directory, a full filesystem, a cross-device move that fails mid-copy — none of which `-w`
# can see. Neither is `mv -f`: forcing over a read-only file would silently overwrite a file the
# user's VCS is holding closed, which is a policy this task has no measurement for and is not the
# installer's posture anywhere else. Every other unhandleable state in this file is declined out loud.
#
# THE MODE IS PRESERVED ACROSS THE `mv`, and preservation is *no change* rather than a safer change.
# The merged text is written to a NEW file and moved over the target, so without the restore the
# target's permissions become whatever the umask says. Measured under `umask 0002`, the behaviour that
# restore replaced moved modes in BOTH directions: 600 → 664 (widened — and 600 is what install 1
# actually produces, since the fresh arm `mv`s from `mktemp`) and 666 → 664 (narrowed). Neither was a
# decision; both were the umask answering a question nobody asked. An earlier note called preservation
# *"strictly more conservative"* and that is false at 0666. It is not conservative, it is inert, which
# is the property a refresh of one region owes a file it does not own. The one mode where preserving
# would have mattered — 0444 — no longer reaches here at all.
#
# `stat -c` is GNU; on a host where it fails the substitution is empty and the chmod is skipped, which
# is the pre-preservation behaviour and is why the `-n` test is there.
#
# RETURNS: 0 merged · 2 the target is not writable, nothing was written · 1 the merge could not be
# written. The caller prints a different sentence for 2 than for 1 because the user's action differs.
#
# THE TEMP SITS BESIDE THE TARGET, NOT BESIDE THE FACTS FILE, AND THAT IS WHAT MAKES `1` TRUE. It was
# `"$2.merged"` — the facts file is a `mktemp`, so the temp lived in `$TMPDIR`, and `mv` is
# `rename(2)` only WITHIN one filesystem. With `/tmp` a tmpfs (the default on Fedora, RHEL, Arch,
# openSUSE and in most containers) or the project on a second drive, the rename degraded to a copy:
# measured 2026-08-17 on the sibling `.codex/hooks.json` write, an interrupted cross-device `mv`
# PRESERVED the destination inode and left it truncated — the target opened and half-written by the
# very statement whose failure this function reports as "nothing was touched". Same directory means
# `rename(2)` on every host, so the target is the old file or the new file and never half of either.
#
# `$$` RATHER THAN `mktemp`, so the temp is created by the awk redirection under the caller's umask
# exactly as `"$2.merged"` was — `mktemp` would give 0600 and change the mode the target ends up
# with on any host where the `stat -c` below returns nothing. One installer runs at a time in one
# project, so the name cannot collide with itself.
#
# WHEN THE TARGET'S DIRECTORY WILL NOT TAKE A FILE the awk redirection now fails where the `mv` used
# to, and the function still returns 1 with the target untouched — the same status and the same
# truth, one statement earlier. `tests/test-install-upgrade-client.sh` arm 8 measures exactly that.
#
# THE MARKERS BELOW ARE FOR EXTRACTION, NOT FOR A SECOND COPY. `codex_layer_path` carries a pair like
# this because two files hold it and the suite compares them byte for byte; this function has exactly
# one copy and nothing to compare. What the pair buys instead is that
# tests/test-install-upgrade-client.sh can `eval` the REAL function and call it directly, which is the
# only way to reach the `mv`-failed arm: no end-to-end fixture can produce a failing rename inside an
# install, so without that arm the status test this function was rewritten for is unasserted — proved
# by mutation, deleting it left the whole file green.
# kinglet:merge-marked-region:begin
merge_marked_region() {
  local target="$1" facts="$2" tmp="$1.kinglet-merge.$$" mode
  [ -w "$target" ] || return 2
  mode="$(stat -c '%a' "$target" 2>/dev/null || true)"
  if awk -v factsfile="$facts" '
      /kinglet:generated:begin/ { print; while ((getline l < factsfile) > 0) print l; skip=1; next }
      /kinglet:generated:end/   { print; skip=0; next }
      !skip { print }
    ' "$target" > "$tmp"; then
    # TESTED, NOT TRUSTED — see this header's opening. `mv`'s status is the whole difference between
    # a merge and a claim of one.
    if mv "$tmp" "$target"; then
      if [ -n "$mode" ]; then chmod "$mode" "$target"; fi
      return 0
    fi
  fi
  rm -f "$tmp"
  return 1
}
# kinglet:merge-marked-region:end

# ── A temp file whose rename into $1 is actually a rename ────────────────────
#
# `mv` is `rename(2)` only WITHIN one filesystem. Across one, coreutils copies — and a copy that is
# interrupted leaves the DESTINATION truncated. Measured 2026-08-17 with `$TMPDIR` on another
# filesystem and a real 5429-byte `.codex/hooks.json` as the destination: after an interrupted
# cross-device `mv` the file was 4096 bytes, `jq` refused it, and the arm that had just failed
# printed *"the previous config (if any) is untouched rather than half-written"*. Under Codex an
# unparseable hook config is a silent ALLOW, so the atomicity was not a nicety.
#
# IT IS NOT AN EXOTIC HOST EITHER. `/tmp` is a tmpfs by default on Fedora, RHEL, Arch, openSUSE and
# in most containers, and any Unity project on a second drive is cross-device even on a
# Debian-family host. `$TMPDIR` is also the user's to set. So every temp this file renames into the
# project is created in the directory it will land in, and the claim holds on every host rather than
# on the one it was written on.
#
# THE FALLBACK IS NOT A SECOND ATOMICITY CLAIM — it preserves the BEHAVIOUR of the states where the
# rename was never going to work. `mktemp` here fails exactly when we cannot create a file in that
# directory, and `rename(2)` needs write and execute on the destination's directory too, so a host
# that refuses the temp refuses the rename. Every caller below already reports that outcome, and the
# fallback keeps it reaching the same `mv`, the same warn, and the same `Not done:` entry rather than
# inventing a new failure shape at the `mktemp`. The one state in which the fallback can still write
# is a cross-device `mv` onto a writable file inside a sealed directory, which coreutils performs by
# truncating the destination in place: non-atomic, which is the pre-2026-08-17 behaviour everywhere.
mktemp_beside() {   # $1 = the directory the file will be renamed into, $2 = a name prefix
  mktemp "$1/$2.XXXXXX" 2>/dev/null || mktemp
}

# count_paths — how many paths a glob matched.
#
# `ls -1 GLOB 2>/dev/null | grep -c . || true` was the idiom here, in fifteen places. It is correct
# on this repository's own filenames and ShellCheck still flags every one (SC2010), which mattered
# from 2026-09-08: the `Shellcheck our scripts` CI step had never run before then, because the step
# ahead of it died on a malformed directive, so twenty findings landed at once the moment it did.
#
# An unmatched glob arrives as its own literal, which is what turns "no matches" into 0 here —
# the same job the `grep -c .` was doing, without `ls` in the pipeline.
count_paths() {
  local n=0 p
  for p in "$@"; do
    if [ -e "$p" ]; then n=$((n + 1)); fi
  done
  printf '%s' "$n"
}

# ── Can this run replace what is at that path? ───────────────────────────────
# True when nothing is there, or when what is there is writable. It answers for the WHOLE-FILE write
# arms what `merge_marked_region`'s own `-w` test answers for the merge, and it exists because the
# merge fix left a second door open on the same condition.
#
# MEASURED 2026-08-17, under a pty, on a project whose AGENTS.md is byte-identical to what install 1
# wrote and merely read-only — which is every submitted, unopened file on a Perforce-managed Unity
# project, no user edit involved: `owned_by_installer` says ours, the write arm reaches
# `mv "$TMP_AG" "$AGENTS_MD"`, `mv` asks `overriding mode 0444?`, and a declined prompt exits 1. That
# `mv` is a bare command, so `set -e` ends the install: `err This install did not finish (exit 1)`,
# rc 1, receipt written for what it had. Loud rather than false — the opposite failure to the merge's
# — and the two arms answering the same condition in opposite ways is the inconsistency this closes.
#
# IT DOES NOT TEST THE PARENT DIRECTORY, AND EVERY ARM IT GUARDS NOW READS `mv`'s STATUS TOO — the
# second half of that sentence is what makes the first half a design rather than a hole. A rename can
# fail for reasons no predicate can see beforehand: a 555 parent, a full filesystem, a cross-device
# copy that dies part-way. This header claimed the backstop existed *"which is why the merge checks
# `mv`'s status as well"* and that was true of the merge and false of both write arms it actually
# guards — measured 2026-08-17 (W1): an `AGENTS.md` that is ours, unedited and WRITABLE, in a project
# directory at 555, passes `can_replace`, and the bare `mv` then fails with `Permission denied` and
# `set -e` ends the run — `err This install did not finish (exit 1)`, payload already on disk, which
# is verbatim the failure this predicate was added to prevent. The class was derived rather than
# spot-checked (`awk '!/^[[:space:]]*#/ && /(^|[^a-zA-Z_])mv[[:space:]]/' install.sh`) and every
# member with a user-visible destination now reports instead of dying; the one that does not is the
# `.claude/` backup rename, where continuing would install a payload over a tree we had just failed to
# preserve, so the abort is the correct outcome and is documented at its site.
#
# So the division of labour is: this predicate is the test that can name the file and print a remedy
# the user can act on before anything is written; the status check is what catches everything it
# cannot see.
#
# ITS CLOSING SENTENCE ALSO OVER-CLAIMED AND IS NARROWED. It read *"forcing over a read-only file
# would silently overwrite a file the user's VCS is holding closed, which is not the installer's
# posture anywhere else. Every other unhandleable state in this file is declined out loud."* The
# second sentence is false one flag away, measured (W4): with `Packages/manifest.json` at 0444,
# `--with-mcp` runs `sed -i` over it, which needs directory write rather than file write, succeeds,
# prints `ok Added …`, and leaves the file rewritten at mode 444 — and, because `sed -i` renames its
# temp into place, at a NEW INODE. So that path both defeats the read-only bit silently and replaces
# the file the user's VCS was tracking rather than editing it. The posture stated here is the
# posture for the two GENERATED ENTRY DOCUMENTS — the files this task is about, and the ones a Codex
# or Claude Code session reads on every turn. Whether the manifest edit should join them is a
# behaviour change on a flagged path with its own backup and decline logic, and it is recorded for the
# ledger rather than made here.
can_replace() {
  [ ! -e "$1" ] || [ -w "$1" ]
}

# ── THE CLASS THIS PREDICATE BELONGS TO, DERIVED FROM A CRITERION RATHER THAN FROM A VERB ────
#
# `mv` was a proxy for the question and not the question. The criterion is: **a statement that
# creates, replaces, appends to or truncates a path the USER can see — project root, `Packages/`,
# `.codex/`, `.agents/` — where a failure leaves that path in a state nobody chose, or is not
# reported.** Derived by enumerating every write verb and every redirection to a variable path
# (`mv`, `cp`, `sed -i`, `ln -s`, `rm`, and `>` / `>>`), not one regex:
#
#   merge_marked_region            CLAUDE.md / AGENTS.md   `-w` + status        reports
#   .claude/ → backup rename       a fresh backup dir      abort, on purpose    see its site
#   fresh CLAUDE.md                CLAUDE.md               status               reports
#   beside-yours                   CLAUDE.md.generated     can_replace + status reports
#   manifest rollback              Packages/manifest.json  status               reports
#   AGENTS.md write                AGENTS.md               can_replace + status reports
#   manifest backup `cp`           …manifest.json.bak      status               declines the flag
#   .gitignore CREATE              .gitignore              status               reports
#   .gitignore append              .gitignore              can_replace + status reports
#   .mcp.json create               .mcp.json               status               reports
#   MCP-SETUP.md copy              MCP-SETUP.md            status               reports
#   .codex/hooks.json              .codex/hooks.json       can_replace + rename reports
#   .codex/config.toml create      .codex/config.toml      status               reports
#   .agents/skills/ link           .agents/skills/<name>   status               counts, reports
#   .agents/skills/ stale prune    .agents/skills/<name>   status               counts, reports, rows
#   .agents/skills/ command copy   .agents/skills/<c>/…    status               counts, reports, rows
#   .agents/ retired-command rm    .agents/skills/<c>/     status               counts, reports, drops the row
#
# AND THE TEMPS, which are writes into the user's tree too and had no rows here until
# 2026-09-08. `mktemp_beside` puts each one beside its destination so the rename that follows is
# a rename and not a cross-device copy — correct for atomicity, and it means four files the user
# can see. None is a silent-failure path: `mktemp_beside` falls back to `$TMPDIR` when the
# destination refuses, and every caller tests the result before writing through it. They are
# listed because a write verb that is not in this table is how the class stops being enumerable,
# which is the one thing this table exists to prevent.
#
#   CLAUDE.md merge temp          .kinglet-claude-md.*    fallback + caller     removed on both paths
#   AGENTS.md merge temp          .kinglet-agents-md.*    fallback + caller     removed on both paths
#   hook-config temp              .codex/.hooks.json.*    fallback + caller     removed on both paths
#   manifest edit temp            Packages/manifest.json.tmp  status            reports; `sed -i` also
#                                                                              leaves its own sedXXXXXX
#                                                                              in that directory, found
#                                                                              only by syscall tracing
#   .codex/ stale-config delete    .codex/hooks.json       status               reports, keeps the row
#   .codex/ mkdir                  .codex/                 status               becomes a skip reason
#
# THE MEMBERS THE VERB COULD NOT SEE, all measured, all **rc 1 mid-install** before the commit that
# closed them — the exact failure this task exists to remove, on the exact trigger the rest of it
# handles, and every one of them found by re-deriving the class rather than by fixing the last one:
#
#   * a read-only `.gitignore` — `printf … >> "$GITIGNORE"` died at Step 7, so `.mcp.json`,
#     `MCP-SETUP.md`, the entire Codex layer and `Next steps:` never ran, with the payload on disk;
#   * an ABSENT `.gitignore` under a sealed project root — `: > "$GITIGNORE"` died in the very next
#     branch, because `can_replace` answers 0 for a path that is not there and the CREATE is a
#     different question from the REPLACE. That one shipped inside the round that fixed its sibling;
#   * a read-only `.codex/hooks.json` of ours — `cat "$HCFG_TMP" > "$CODEX_HOOKS_JSON"` died
#     mid-Codex-layer. That one is additionally a TRUNCATING, NON-ATOMIC write: a failure after the
#     open leaves a half-written hook config, which Codex cannot parse, which is a silent ALLOW —
#     the very outcome the block around it exists to refuse. It writes through a rename now, and the
#     temp is created inside `.codex/` so that the rename is a rename on every host (`mktemp_beside`);
#   * `.agents/skills/` — the directory this criterion sentence has named since it was written, with
#     no row in this table until 2026-08-17. A read-only converted command skill killed the `cp`; a
#     sealed skill root killed the `ln -s` and the stale-link `rm -f`. `is_modified` compares content
#     and cannot see a mode, so an unedited file a VCS holds read-only takes the write arm every time.
#
# WHAT IS DELIBERATELY LEFT ABORTING, and why each is not the same case:
#
#   * the `.claude/` → backup rename, documented at its own site: nothing has been written yet and
#     continuing would install over a tree we failed to preserve;
#   * every write under `.claude/` itself — the payload loop, the scripts loop, the receipt. That
#     directory is the toolkit's, not the user's, so a failure there is a failed install rather than
#     a user file left in a state nobody chose, and the receipt trap still records what landed;
#   * `sed -i` on `Packages/manifest.json`. It SUCCEEDS on a 0444 file, and "it succeeds" is not the
#     same claim as "it is safe" — this line asserted the first as though it settled the second.
#     Measured end to end with `--with-mcp` against a 0444 manifest: `ok Added com.coplaydev.unity-mcp
#     to manifest.json`, rc 0, and afterwards the file has a NEW INODE with mode 444 and the owner
#     preserved. So the read-only bit — the one signal a VCS uses to say *do not edit this* — is
#     silently defeated, and the file the user's tooling was tracking has been replaced rather than
#     modified. Every other user-visible write in this table now refuses that state and names it;
#     this one edits it and prints `ok`. The decision to leave it stands — it is a behaviour change
#     on a flagged path with its own backup and rollback, and it belongs with a measurement of what
#     Perforce and Unity do with a replaced manifest inode — but the ground recorded here is now what
#     was measured rather than the half of it that made the decision look free.
can_replace_or_report() {   # $1 = path, $2 = what it is, $3 = the re-run command
  if can_replace "$1"; then return 0; fi
  warn "$2 is read-only, so it was NOT written and nothing else was changed at that path."
  warn "Make it writable (under Perforce: check it out) and re-run $3."
  return 1
}

# ── Did a PREVIOUS run of this installer write this path? ────────────────────
# Presence of a row, whatever its origin — deliberately weaker than `owned_by_installer`, which also
# requires the bytes to be unchanged. It answers the one question that separates "our file, which the
# user has since edited" from "a file of the user's that we have never written", and it is the guard
# that keeps the `user-modified` row for AGENTS.md fail-closed: a project whose AGENTS.md predates
# every install has no row, gets no row, and `uninstall.sh --purge` therefore never reaches it.
#
# $RECEIPT still holds the PREVIOUS run's receipt at every call site — see owned_by_installer's own
# paragraph on that, which enumerates the four statements that could have changed it and does not.
receipt_has() {
  [ -f "$RECEIPT" ] || return 1
  awk -F'\t' -v want="$1" '$1 == want { found = 1 } END { exit !found }' "$RECEIPT"
}

# ── The .gitignore decision ──────────────────────────────────────────────────
# Ask git what it already ignores rather than grepping for our exact lines. A project that ignores
# `/.claude/` wholesale — a perfectly sensible choice, and one real projects make — is already
# covered, and appending our entries to it is just noise in someone else's file.
#
# TWO KINDS, NOT ONE LIST, AND MERGING THEM WOULD BE A BUG. `WANT_IGNORED` holds concrete PROBE
# PATHS to hand to `git check-ignore`, which needs a path and can never be handed a negation.
# `GITIGNORE_ENTRIES` holds the PATTERNS actually appended. The correspondence is 3 → 4, not 1:1:
# `.claude/state/session.json` is the probe for both `.claude/state/*` and the negation
# `!.claude/state/.gitkeep`. Both counts are DERIVED wherever they are used rather than written into
# a sentence — the sentence that used to sit here said "three" for a whole wave after a fourth
# pattern was added below it.
#
# THE PLAN IS COMPUTED TWICE — once by the dry-run block, once by Step 7 — AND THE TWO AGREE ONLY
# BECAUSE NOTHING BETWEEN THEM TOUCHES ITS INPUTS. Those inputs are exactly two: the contents of
# $GITIGNORE, and git's ignore rules for $PROJECT_DIR. Steps 4–6 write only under $CLAUDE_DIR, plus
# CLAUDE.md and CLAUDE.md.generated at the root, and install.sh runs no git command that mutates an
# index or a config. True at the time of writing and asserted NOWHERE — if a future step gains a
# write to .gitignore, or runs `git add`/`git config` on the project, Step 7's recomputation will
# silently disagree with what the dry run already announced. The fix then is to call gitignore_plan
# ONCE, here, and pass the result down; it is two calls today only because the dry run exits before
# Step 7 ever runs and a single call would be dead weight on that path.
#
# A NEWLINE HELD IN A VARIABLE, so no `$'…'` appears inside a parameter-expansion pattern below.
# bash 3.2's parser cannot be exercised from this host, a planned macOS pass has to survive it, and
# `"$NL"` inside the pattern is unambiguous in every bash. Cheap insurance.
#
# THIS COMMENT USED TO CITE scripts/studio-doctor.sh AS PRECEDENT for `${VAR%%$'\n'*}` — "it uses it
# twice" — and read as though the spelling were inherited and only this file were opting out. It was
# not inherited. Both of that file's sites were written by 6a2793e on 2026-08-12, and this comment by
# 82dc293 the next morning, so the precedent cited was thirteen hours old and the wave's own. There is
# no such precedent now: studio-doctor.sh holds an `NL` of its own and both files spell it the same
# way. If you are about to add a third site, check for the old spelling rather than assuming:
#   grep -rn "%%\$'" --include='*.sh' .
NL=$'\n'
GITIGNORE="$PROJECT_DIR/.gitignore"
WANT_IGNORED='.claude/settings.local.json
.claude/state/session.json
.claude.backup.20260101120000/'
# uninstall.sh writes its backup to .claude.backup.<timestamp>/ at the project root. Without the
# last entry, every uninstall leaves an untracked directory that dirties `git status` in the user's
# own repo.
GITIGNORE_ENTRIES='.claude/settings.local.json
.claude/state/*
!.claude/state/.gitkeep
.claude.backup.*/'
GITIGNORE_ENTRY_COUNT=$(printf '%s\n' "$GITIGNORE_ENTRIES" | grep -c . || true)

already_ignored() {
  git -C "$PROJECT_DIR" rev-parse --git-dir >/dev/null 2>&1 || return 1
  git -C "$PROJECT_DIR" check-ignore -q "$1" 2>/dev/null
}

# THE DECISION IS TWO-STAGE, and an announcement built on the first stage alone is wrong in every
# project git does not track — which is the shape of every second install in such a project.
#
#   Stage 1  `already_ignored` per probe path. OUTSIDE a work tree it cannot answer and returns 1
#            for everything, so this stage says "needed" on every run of a non-git project and can
#            never be the thing that declines there.
#   Stage 2  the per-entry `grep -qxF` that used to live inside `add_ignore`. This is what actually
#            declines on that second install: all four literals are already lines in the file from
#            install 1, nothing is appended, and the run prints "already has our entries".
#
# Prints a verdict word on the first line, then the entries an append would add, in order:
#   covered   a .gitignore exists and git ignores every probe path — Step 7 leaves the file alone
#   present   the block runs, and every entry is already a line in the file — nothing is appended
#   append    the lines that follow are exactly what Step 7 appends, in the order it appends them
gitignore_plan() {
  local p e needed=0 missing=''
  # Stage 1 can only decline when there is a file to leave alone — the real run's guard is
  # `NEEDED -eq 0` AND `-f "$GITIGNORE"` — so with no file the probes cannot change the outcome.
  if [ -f "$GITIGNORE" ]; then
    while IFS= read -r p; do
      [ -n "$p" ] || continue
      already_ignored "$p" || needed=1
    done <<< "$WANT_IGNORED"
    if [ "$needed" -eq 0 ]; then printf 'covered\n'; return 0; fi
  fi
  # Stage 2. `grep` reads a FILE ARGUMENT, not a pipe, so `-q`'s exit-on-first-match cannot SIGPIPE
  # a writer under `set -euo pipefail`. A missing file makes grep exit 2, which is "not present" —
  # the create path's correct answer, and the reason no `-f` test is needed here.
  while IFS= read -r e; do
    [ -n "$e" ] || continue
    grep -qxF -- "$e" "$GITIGNORE" 2>/dev/null || missing="${missing}${e}"$'\n'
  done <<< "$GITIGNORE_ENTRIES"
  if [ -z "$missing" ]; then printf 'present\n'; return 0; fi
  printf 'append\n%s' "$missing"
}

# ── The Packages/manifest.json decisions ─────────────────────────────────────
# Derived from $MANIFEST rather than written out again, so the receipt row, the announcement, and
# the file they both name cannot disagree. A row whose path is one character off is a row
# uninstall.sh silently declines to act on, which on disk is indistinguishable from no row at all.
MANIFEST_BAK_REL="${MANIFEST#"$PROJECT_DIR"/}.bak"

# Would a --with-* flag passed to THIS run still have an edit to make? `add_manifest_dependency`
# returns early when there is no manifest or the package is already in it, and an early return
# copies nothing — so neither the edit nor the backup happens.
manifest_edit_pending() {
  [ -f "$MANIFEST" ] || return 1
  if [ "$WITH_MCP" -eq 1 ] && ! grep -q "$MCP_PKG_NAME" "$MANIFEST" 2>/dev/null; then return 0; fi
  if [ "$WITH_INPUT_SYSTEM" -eq 1 ] && [ "$HAS_INPUT_SYSTEM" -eq 0 ]; then return 0; fi
  return 1
}

# D11's decline, asked the way `add_manifest_dependency` asks it. A Packages/manifest.json.bak that
# exists and is not ours abandons THE WHOLE FLAG rather than overwriting the user's file — so the
# manifest edit does not happen either, and an announcement that promised it would be wrong in the
# direction that destroys trust. `MANIFEST_BAK_KEPT`'s disjunct is deliberately absent here: it
# answers "this run already made the copy", and at dry-run time no run has.
manifest_bak_is_foreign() {
  [ -e "$MANIFEST.bak" ] || return 1
  if owned_by_installer "$MANIFEST_BAK_REL" ''; then return 1; fi
  return 0
}

# Would THIS run create Packages/manifest.json.bak and keep it? FIVE conditions gate that file in
# `add_manifest_dependency`, and FOUR of them are answerable from here:
#
#   1. a manifest exists                        — asked, inside manifest_edit_pending
#   2. some flag still has an edit to make      — asked, manifest_edit_pending
#   3. it is not D11's decline                  — asked, manifest_bak_is_foreign
#   4. the surgical `sed` insert SUCCEEDED      — NOT ASKABLE HERE. The failure arm runs
#                                                 `mv "$MANIFEST.bak" "$MANIFEST"` and leaves no
#                                                 backup behind, and the only way to know in advance
#                                                 is to rehearse the edit on a temp copy. The
#                                                 announcement NAMES this condition instead of
#                                                 pretending to have evaluated it.
#   5. git does not track Packages/manifest.json — asked. When git tracks it, git IS the backup and
#                                                 the .bak is deleted straight after the edit.
manifest_bak_would_be_kept() {
  manifest_edit_pending || return 1
  if manifest_bak_is_foreign; then return 1; fi
  if git -C "$PROJECT_DIR" ls-files --error-unmatch Packages/manifest.json >/dev/null 2>&1; then
    return 1
  fi
  return 0
}

if [ "$DRY_RUN" -eq 1 ]; then
  printf '\n%s\n' "${BOLD}Would install:${NC}"
  printf '  %s files into %s\n' "$PAYLOAD_COUNT" "$CLAUDE_DIR"
  printf '  %s files from scripts/ into %s/scripts\n' "$SCRIPTS_COUNT" "$CLAUDE_DIR"
  if [ "$ORPHAN_COUNT" -gt 0 ]; then
    printf '  remove %s file(s) this payload no longer ships:\n' "$ORPHAN_COUNT"
    printf '%s' "$ORPHANS" | while IFS= read -r o; do [ -n "$o" ] && printf '       %s\n' "$o"; done
  fi
  [ "$ORPHAN_KEPT_COUNT" -gt 0 ] && printf '  keep %s removed-from-payload file(s) you edited\n' "$ORPHAN_KEPT_COUNT"
  # MODIFIED_FILES / EDITED_FILES / UNREADABLE_ORIGINS are always set; KEPT/MOD_COUNT are not defined
  # until Step 5 and would be an unbound-variable death under `set -u`.
  #
  # COUNTED OFF EDITED_FILES, NOT THE UNION, for the reason the real run's line is: `you modified` has
  # to be true of every file in the number. The union includes the unreadable-origin bucket, which is
  # kept for a different reason and gets its own line here too — an announcement that folded them
  # together would be the dry run restating a claim the real run had just stopped making, which is
  # exactly the drift this block exists to prevent.
  #
  # NEITHER LINE CARRIES A PATH, so neither mints a claim in tests/test-install-dryrun.sh's parser:
  # that parser reads the first field, and `keep` has neither a dot nor a slash, so it classifies as
  # prose rather than as a promise about a path.
  DRY_MOD=$(printf '%s' "$EDITED_FILES" | grep -c . || true)
  [ "$DRY_MOD" -gt 0 ] && printf '  keep %s file(s) you modified\n' "$DRY_MOD"
  DRY_UNREADABLE=$(printf '%s' "$UNREADABLE_ORIGINS" | grep -c . || true)
  [ "$DRY_UNREADABLE" -gt 0 ] && \
    printf '  keep %s file(s) whose receipt origin cannot be read — kept, and recorded as yours\n' \
      "$DRY_UNREADABLE"

  # Report the CLAUDE.md branch we would actually take. This said "CLAUDE.md (generated)"
  # unconditionally, which is a lie in the one case that matters: against a project that already has
  # a CLAUDE.md, the real install writes CLAUDE.md.generated and leaves theirs alone. A dry run that
  # misreports the only step capable of destroying work is worse than having no dry run.
  #
  # THE MALFORMED ARM IS HERE FOR THAT SENTENCE AND NOT FOR SYMMETRY. Both arms above used to be one
  # `grep -q ...begin`, so a begin-only CLAUDE.md was announced as `refresh the generated section
  # only; your prose untouched` by the dry run and then amputated by the real run — the dry run
  # promising exactly the thing the real run destroyed, on the only step that can destroy work.
  # `marked_region_state` is called, not restated, for the reason this block's header gives.
  #
  # WRITABILITY IS ASKED FIRST, AND IT IS ASKED WITH THE RUN'S OWN PREDICATE. The read-only refusals
  # were added to the real run on 2026-08-17 and this block was not taught about them in the same
  # commit, which converted a shared error into a divergence: before, the announcement and the run
  # both claimed a refresh and both were wrong; after, only the run was truthful, so the dry run
  # promised a write the real run declines. That is the S3b defect this block's own header cites as
  # its reason for existing, arriving through the fix for a different one. `can_replace` is called
  # rather than restated for the reason every other predicate here is — a copy of a condition is a
  # second definition of it.
  DRY_MARKER_STATE="$(marked_region_state "$PROJECT_DIR/CLAUDE.md")"
  if [ "$DRY_MARKER_STATE" = absent ]; then
    printf '  CLAUDE.md (new — generated)\n'
  elif [ "$DRY_MARKER_STATE" = wellformed ]; then
    # WRITABILITY IS ASKED **INSIDE** THIS ARM, NOT AHEAD OF THE WHOLE BLOCK — and the first version
    # of this fix asked it ahead, which closed the reported divergence and opened a worse one. The
    # only arm whose write CLAUDE.md's own mode can stop is this one: the merge. The marker-less arm
    # below writes `CLAUDE.md.generated` and never touches `CLAUDE.md` at all, so a read-only
    # CLAUDE.md does not select it — and a test in front of the block short-circuited before that
    # arm's announcement, leaving the run to CREATE a project-root file the dry run never named.
    # `tests/test-install-dryrun.sh`'s own first oracle is written for exactly that: *"the real run
    # wrote X and the dry run never named it — an unannounced write at the project root."*
    #
    # ONE PREDICATE ASKED IN TWO PLACES IS ONE PREDICATE ONLY IF BOTH PLACES ASK IT AT THE SAME POINT
    # IN THEIR OWN LOGIC. That is the lesson, and it is why this test sits where the real run's
    # `merge_marked_region` call sits rather than where it was convenient to put it.
    if ! can_replace "$PROJECT_DIR/CLAUDE.md"; then
      # `NOT touched` is one of tests/test-install-dryrun.sh's recognised decline phrases; the
      # sentence after it is the remedy the real run prints, so a reader comparing the two sees one
      # answer.
      printf '  CLAUDE.md is read-only — its generated section is NOT touched; make it writable to have it refreshed\n'
    else
      printf '  CLAUDE.md — refresh the generated section only; your prose untouched\n'
    fi
  elif [ "$DRY_MARKER_STATE" != none ]; then
    # ONE LINE, ONE PATH. This arm writes nothing at all — not CLAUDE.md, not CLAUDE.md.generated —
    # so it names neither of the other two paths. `NOT touched` is one of the decline phrases
    # tests/test-install-dryrun.sh recognises; a rewording that leaves that list reads as a PROMISE
    # of a write this arm does not make.
    printf '  CLAUDE.md — %s, so it is NOT touched and nothing is generated\n' \
      "$(marked_region_problem "$DRY_MARKER_STATE")"
  else
    # TWO FILES, TWO FATES, AND THIS ARM USED TO NAME ONE AND DESCRIBE THE OTHER:
    #
    #   CLAUDE.md.generated — yours exists and has no markers, so it is NOT touched
    #
    # "yours", "has no markers" and "NOT touched" are all true of CLAUDE.md. The file the line NAMES
    # is the one this arm CREATES. So the dry run promised to leave alone the only path it was about
    # to write, on the branch a user reaches by already having a CLAUDE.md of their own — which is
    # exactly the reader who is checking whether their file is safe.
    #
    # Split, so each path gets its own sentence and the guard can read one claim per line.
    printf '  CLAUDE.md — yours has no generated markers, so it is NOT touched\n'
    # THE SAME PREDICATE THE REAL RUN USES, called rather than restated: an announcement computed
    # from a copy of the write's condition is a second definition that drifts, which is the failure
    # this whole block has already paid for twice. owned_by_installer is defined above this point,
    # $RECEIPT still holds the previous run's receipt here, and the arguments match the real run's
    # call — '' for the reference copy, because this file is generated per project and has none.
    if [ -e "$PROJECT_DIR/CLAUDE.md.generated" ] && ! owned_by_installer 'CLAUDE.md.generated' ''; then
      printf '  CLAUDE.md.generated exists and is not ours — would leave alone, and generate nothing\n'
    elif ! can_replace "$PROJECT_DIR/CLAUDE.md.generated"; then
      # The `.generated` arm's own writability refusal, announced with the arm that makes it. Its
      # ownership test comes first here exactly as it does in the real run — the file being read-only
      # only matters once we know it is not the user's.
      printf '  CLAUDE.md.generated is read-only — it is NOT touched, and nothing is generated beside your CLAUDE.md\n'
    else
      printf '  CLAUDE.md.generated — generated beside your own CLAUDE.md, for you to merge by hand\n'
    fi
  fi

  # THE SAME PLAN STEP 7 ACTS ON, called rather than restated. The line here was unconditional and
  # named two of the four entries: it promised an edit on every run, including the two runs that
  # make none, and under-described the one run that does.
  #
  # THE DECLINE WORDING IS A CONTRACT WITH tests/test-install-dryrun.sh'S PARSER, NOT FREE PROSE.
  # That file reads a line whose first field is a path as a PROMISE unless the line carries one of
  # the phrases it recognises. `already covered` and `no change` are both in that set; the real
  # run's own "already has our entries" is deliberately NOT, because the bias is toward a loud false
  # red rather than a silent false green. Both declines below therefore carry the recognised
  # spelling and say WHICH of the two mechanisms declined in the prose after it.
  # NOT A BARE ASSIGNMENT — see Step 7's call site, which carries the measurement. A death here
  # would be harmless (nothing is written on this path), but the two readers are kept identical on
  # purpose, and an idiom that is safe in only one of the two places it appears is one edit from
  # being moved to the other.
  DRY_GITIGNORE_RC=0
  DRY_GITIGNORE_PLAN="$(gitignore_plan)" || DRY_GITIGNORE_RC=$?
  [ "$DRY_GITIGNORE_RC" -eq 0 ] || DRY_GITIGNORE_PLAN="failed with status $DRY_GITIGNORE_RC"
  case "${DRY_GITIGNORE_PLAN%%"$NL"*}" in
    covered)
      printf '  .gitignore — git already ignores every path we would add, so it is already covered — no change\n' ;;
    present)
      printf '  .gitignore — all %s of our entries are already lines in it, so it is already covered — no change\n' \
        "$GITIGNORE_ENTRY_COUNT" ;;
    append)
      # ONE LINE, WITH THE ENTRIES ON IT RATHER THAN INDENTED UNDER IT. An entry per line would give
      # each entry a first field of its own and mint claims about paths nothing writes.
      DRY_GITIGNORE_ADD="${DRY_GITIGNORE_PLAN#*"$NL"}"
      DRY_GITIGNORE_N=$(printf '%s\n' "$DRY_GITIGNORE_ADD" | grep -c . || true)
      # awk drains its input to the end, so this pipeline cannot SIGPIPE the writer.
      DRY_GITIGNORE_LIST="$(printf '%s\n' "$DRY_GITIGNORE_ADD" \
        | awk 'NF { if (n++) printf ", "; printf "%s", $0 } END { printf "\n" }')"
      # WRITABILITY INSIDE THE ARM THAT WRITES, exactly as the two entry documents' announcements ask
      # it — and this arm needed it the moment Step 7 gained the refusal, in the same commit.
      # Measured before this line existed: `append 4 entries: …` from the dry run, `is read-only, so
      # it was NOT written` from the run, one fixture. That is the divergence this whole block exists
      # to prevent, reintroduced by the fix for a different member of the same class, which is the
      # third time this wave has done it. `NOT touched` is one of tests/test-install-dryrun.sh's
      # recognised decline phrases.
      if ! can_replace "$GITIGNORE"; then
        printf '  .gitignore is read-only — it is NOT touched, and none of its %s entries would be appended\n' \
          "$DRY_GITIGNORE_N"
      elif [ -f "$GITIGNORE" ]; then
        printf '  .gitignore — append %s entries: %s\n' "$DRY_GITIGNORE_N" "$DRY_GITIGNORE_LIST"
      else
        printf '  .gitignore (new) — create it, with %s entries: %s\n' "$DRY_GITIGNORE_N" "$DRY_GITIGNORE_LIST"
      fi ;;
    *)
      # THE SAME FALLBACK STEP 7 TAKES, IN THE SAME SHAPE, and that symmetry is the point: the whole
      # premise of one shared plan is that the two readers cannot diverge. Without an explicit
      # `append)` above, an unrecognised verdict fell into the append branch here and announced
      # `append 0 entries:` while Step 7 warned and wrote nothing — a promise with no write, in the
      # one file built to make that impossible.
      #
      # A DECLINE, AND THE ACTIVE VOICE IS LOAD-BEARING: tests/test-install-dryrun.sh's `declre`
      # carries `would leave alone`, not `would be left alone`. The passive is a substring miss and
      # classifies as a PROMISE.
      printf '  .gitignore — its plan could not be computed — would leave alone\n' ;;
  esac

  # ── Packages/manifest.json, its backup, and the flags ──────────────────────
  # LEAD WITH THE PATH. These lines used to begin `--with-mcp:` / `--with-input-system:`, so their
  # first field was a FLAG NAME. A reader scanning the block for the files a run touches — and
  # tests/test-install-dryrun.sh's parser, which reads the first field — saw no claim about
  # Packages/manifest.json at all, while the real run edited it in place at the project root.
  #
  # The third arm is D11's decline, and it is new. A Packages/manifest.json.bak that is not ours
  # abandons the flag rather than overwriting it, so the edit this block used to promise
  # unconditionally does not happen.
  #
  # `would leave alone`, NOT `would be left alone`. tests/test-install-dryrun.sh's `declre` matches
  # the ACTIVE phrase as a substring; the passive misses it and classifies the line as a PROMISE —
  # and since D11's decline writes nothing at all, that is a red on a correct installer. The passive
  # shipped here for one round and the fixture below now guards the wording.
  #
  # BOTH LINES CARRY THE SAME HEDGE, and the symmetry is the fix rather than the decoration. The
  # surgical `sed` insert can fail — a manifest with no "dependencies" key matches nothing — and its
  # failure arm runs `mv "$MANIFEST.bak" "$MANIFEST"`, leaving the manifest UNCHANGED and NO backup.
  # Both files are equally absent from that outcome, so hedging the derived file and stating the
  # primary one flat read as though the edit were certain and only its by-product conditional.
  if [ "$WITH_MCP" -eq 1 ]; then
    if [ ! -f "$MANIFEST" ]; then
      printf '  Packages/manifest.json — none in this project, so --with-mcp would skip\n'
    elif grep -q "$MCP_PKG_NAME" "$MANIFEST" 2>/dev/null; then
      printf '  Packages/manifest.json — %s already present, so --with-mcp would skip\n' "$MCP_PKG_NAME"
    elif manifest_bak_is_foreign; then
      printf '  Packages/manifest.json — %s is not ours, so --with-mcp is declined — would leave alone\n' \
        "$MANIFEST_BAK_REL"
    else
      printf '  Packages/manifest.json — add %s to "dependencies", if the edit succeeds (--with-mcp)\n' \
        "$MCP_PKG_NAME"
    fi
  fi
  if [ "$WITH_INPUT_SYSTEM" -eq 1 ]; then
    if [ ! -f "$MANIFEST" ]; then
      printf '  Packages/manifest.json — none in this project, so --with-input-system would skip\n'
    elif [ "$HAS_INPUT_SYSTEM" -eq 1 ]; then
      printf '  Packages/manifest.json — %s already present, so --with-input-system would skip\n' \
        "$INPUT_SYSTEM_PKG_NAME"
    elif manifest_bak_is_foreign; then
      printf '  Packages/manifest.json — %s is not ours, so --with-input-system is declined — would leave alone\n' \
        "$MANIFEST_BAK_REL"
    else
      printf '  Packages/manifest.json — add %s to "dependencies", if the edit succeeds (--with-input-system)\n' \
        "$INPUT_SYSTEM_PKG_NAME"
    fi
  fi

  # OUTSIDE THE FLAGS, NOT JUST OUTSIDE THE BRANCHES — Step 8's receipt row already states this
  # placement rule in those words, and the announcement was never given the same treatment. On every
  # install after the first the user passes no --with-* flag, so the branch that MAKES this file
  # does not run, while the file sits on disk and the receipt goes on claiming it. An announcement
  # inside `if [ "$WITH_MCP" -eq 1 ]` is silent on exactly the path every user is on after install 1.
  #
  # TWO STATES, TWO VERDICTS, AND THEY ARE NOT INTERCHANGEABLE:
  #   this run would create it   → a PROMISE. The real run writes that path.
  #   an earlier run created it  → a DECLINE. This run re-claims it in the receipt and does not
  #                                touch a byte of it, so promising it would be an announcement with
  #                                no write — the other direction of the same defect.
  # `owned_by_installer` is the disjunct that can answer on a flagless run, and it is the same call
  # Step 8's row makes, with the same '' reference argument: this file is a copy of the user's own
  # manifest, so the toolkit ships no reference copy to compare it against.
  if manifest_bak_would_be_kept; then
    # THE ONE CONDITION THIS CANNOT EVALUATE IS NAMED RATHER THAN ASSUMED AWAY — see
    # manifest_bak_would_be_kept's fourth condition. "if the edit succeeds" is a smaller claim than
    # the run can break.
    printf '  %s — kept as the pre-edit backup if the edit succeeds, and recorded as ours to remove\n' \
      "$MANIFEST_BAK_REL"
  elif owned_by_installer "$MANIFEST_BAK_REL" ''; then
    printf '  %s — the backup an earlier run kept; still ours and still claimed, contents NOT touched\n' \
      "$MANIFEST_BAK_REL"
  fi
  [ -n "$BACKUP_DIR" ] && printf '  backup: %s\n' "$(basename "$BACKUP_DIR")"
  if [ ! -f "$PROJECT_DIR/.mcp.json" ]; then
    printf '  .mcp.json (new — UnityMCP -> http://localhost:8080/mcp)\n'
  elif grep -Eq '"(unityMCP|UnityMCP)"' "$PROJECT_DIR/.mcp.json" 2>/dev/null; then
    printf '  .mcp.json already has a unityMCP/UnityMCP entry — would leave alone\n'
  else
    printf '  .mcp.json exists without unityMCP/UnityMCP — would print the block, not rewrite\n'
  fi

  # Report the MCP-SETUP.md branch too, and for the reason directly above: Step 8c copies it into the
  # project root, records it in the receipt as toolkit-owned, and this block said nothing about it —
  # so the dry run silently under-described a write landing outside .claude/, where a user is least
  # expecting one. That step exists because the summary once pointed at a file the installer never
  # installed; the install half was fixed and the consent half was left open.
  #
  # The copy is conditional — it never overwrites an existing file — so an unconditional line here
  # would promise a file the real run skips: this block's own bug in mirror image. The condition is
  # the same one Step 8c tests, read against $PROJECT_DIR the way the CLAUDE.md branch above does
  # ($MCP_SETUP_MD is not defined until the real-run path, which we never reach here).
  #
  # The skip branch says "already exists", not "yours exists", and speaks only of *contents*. Both
  # narrowings are load-bearing, and the wording above earns neither:
  #   - This branch has no discriminator for who wrote the file. On a re-run the file present is the
  #     toolkit's, written by the previous run, so "yours" is false in the installer's own upgrade
  #     path. The CLAUDE.md branch may say "yours" because `marked_region_state`'s test has
  #     already proved the file is not ours; .mcp.json, which has no such test either, correctly
  #     claims nothing. (This read line 274 until 2026-08-14, by which point line 274 was a comment
  #     about the scripts write group.)
  #   - "contents", because that is the whole of what this branch can vouch for. It cannot speak to
  #     ownership: Step 8c decides that by comparing the file on disk against the toolkit's copy and
  #     against the previous receipt's checksum, and doing either here would be a second copy of
  #     that decision living in the announcement — the drift this file has already paid for twice.
  #     (Until 2026-08-12 this bullet said ownership was unknowable because the row was written only
  #     on create, so an upgrade dropped it and uninstall.sh left the file behind. That defect is
  #     closed; see owned_by_installer. The line still does not reach into ownership, now because it
  #     should not rather than because it cannot.)
  if [ -f "$SCRIPT_DIR/MCP-SETUP.md" ]; then
    if [ ! -f "$PROJECT_DIR/MCP-SETUP.md" ]; then
      printf '  MCP-SETUP.md (new — the MCP bridge setup guide)\n'
    else
      printf '  MCP-SETUP.md already exists — its contents are NOT touched\n'
    fi
  fi
  # ── The Codex CLI layer ────────────────────────────────────────────────────
  # ANNOUNCED, BECAUSE THIS ARM IS THE ONE THAT WRITES OUTSIDE .claude/ THE MOST. Three of its five
  # project paths are at the root or in directories no Claude Code install creates, and one optional
  # step leaves the project entirely. A dry run silent about those is worse than no dry run — that
  # is this block's own ruling, already paid for twice above, applied to the newest writes.
  #
  # The counts are DERIVED from the same trees the real run walks, so the announcement cannot promise
  # a number the write does not produce.
  if [ "$CLIENT" = codex ]; then
    # FOUR VERDICTS, NOT ONE, AND THE UNCONDITIONAL LINE WAS WRONG ON THE BRANCH THAT MATTERS. This
    # read `AGENTS.md — the Codex entry document (generated; Codex injects it whole)` on every run,
    # including the run against a project whose AGENTS.md the real install declines to touch — the
    # same defect the CLAUDE.md branch above was built to end, in the newest write, and the same one
    # S3b in tests/test-install-ownership.sh guards one file over. Measured 2026-08-17 on a urp
    # fixture with a user-owned AGENTS.md: the dry run promised a generated document and the real run
    # printed `keeping yours, untouched`.
    #
    # THE PREDICATES ARE THE REAL RUN'S, CALLED RATHER THAN RESTATED — Step 3b's rule, and the reason
    # this block computes nothing of its own. `$RECEIPT` still holds the previous run's receipt here,
    # which is what lets `receipt_has` answer at all.
    #
    # THE DECLINE PHRASINGS ARE A CONTRACT WITH tests/test-install-dryrun.sh'S PARSER: a line whose
    # first field is a path reads as a PROMISE unless it carries one of that file's recognised
    # phrases. `NOT touched` and `would keep yours` are both in that set.
    #
    # `-e` AND NOT THE `absent` TOKEN ON THE FIRST ARM, because they are not the same question. A
    # DIRECTORY at that path makes `marked_region_state` say `absent` — it opens with `[ -f ]` — while
    # the real run's `[ -e ]` sees it and keeps it. Reading the token here would promise a generated
    # file for the one shape where `mv` would move our file INSIDE the user's directory.
    #
    # WRITABILITY FIRST, AND BEFORE OWNERSHIP. The real run refuses a read-only AGENTS.md in BOTH its
    # arms — the merge (rc 2) and the whole-file write (`can_replace`) — so an announcement that asked
    # about ownership first would promise to generate over a file the run declines. Measured
    # 2026-08-17 before this arm existed: `AGENTS.md — the Codex entry document (generated…)` from the
    # dry run, `warn AGENTS.md is read-only, so it was NOT regenerated` from the run, same fixture.
    DRY_AGENTS_STATE="$(marked_region_state "$PROJECT_DIR/AGENTS.md")"
    if [ ! -e "$PROJECT_DIR/AGENTS.md" ] || owned_by_installer 'AGENTS.md' ''; then
      # WRITABILITY INSIDE THE ARM, for the reason the CLAUDE.md block above states at length: the
      # arms this file's mode can stop are the two that WRITE it — the whole-file write here and the
      # merge below. It cannot stop `kept-yours`, and asking ahead of the block made the dry run tell
      # the owner of a read-only file of THEIRS to "make it writable to have it generated", which is
      # false (making it writable leaves it kept) and contradicted the real run's own remedy in the
      # same breath — N-4's defect, reintroduced in the announcement by the commit that fixed it in
      # the run.
      if ! can_replace "$PROJECT_DIR/AGENTS.md"; then
        printf '  AGENTS.md is read-only — it is NOT touched; make it writable to have it regenerated\n'
      else
        printf '  AGENTS.md — the Codex entry document (generated; Codex injects it whole)\n'
      fi
    elif [ "$DRY_AGENTS_STATE" = wellformed ] && receipt_has 'AGENTS.md'; then
      if ! can_replace "$PROJECT_DIR/AGENTS.md"; then
        printf '  AGENTS.md is read-only — its generated section is NOT touched; make it writable to have it refreshed\n'
      else
        printf '  AGENTS.md — refresh the generated section only; your prose untouched\n'
      fi
    elif [ "$DRY_AGENTS_STATE" != none ] && [ "$DRY_AGENTS_STATE" != absent ] \
         && [ "$DRY_AGENTS_STATE" != wellformed ]; then
      # `!= wellformed` for the reason the real run's decline arm carries it: a well-formed pair in a
      # file no previous run wrote is the user's own file, and diagnosing it as a marker fault states
      # something false about it. Both spellings carry the exclusion because both are the same
      # decision, and this block's whole rule is that the two must not disagree.
      printf '  AGENTS.md — %s, so it is NOT touched and nothing is generated\n' \
        "$(marked_region_problem "$DRY_AGENTS_STATE")"
    else
      printf '  AGENTS.md exists and is not ours — would keep yours, and generate nothing\n'
    fi
    DRY_SKILL_N=$(count_paths "$SCRIPT_DIR/.claude/skills"/*/)
    DRY_CMD_N=$(count_paths "$SCRIPT_DIR/.claude/commands"/*.md)
    printf '  .agents/skills/ — %s symlink(s) into .claude/skills/ and %s converted command skill(s)\n' \
      "$DRY_SKILL_N" "$DRY_CMD_N"
    # FOUR VERDICTS HERE TOO, AND THIS LINE WAS AN UNCONDITIONAL PROMISE UNTIL 2026-08-17 — WRITTEN
    # UNCONDITIONAL BY THE SAME COMMIT THAT TAUGHT THE REAL RUN TO REFUSE. Measured on a `--client
    # codex` project with `.codex/hooks.json` at 0444: this line promised the config and the run
    # printed `warn .codex/hooks.json is read-only, so it was NOT written`. That is the divergence
    # this block has now opened five times, and the fifth arrived one screen from the fourth, in the
    # commit dispatched to close it.
    #
    # THE ARMS ARE THE RUN'S, IN THE RUN'S ORDER: its skip reasons first, then the not-ours keep,
    # then the read-only refusal. The two skip reasons asked here are the two that are OBSERVABLE
    # now — the project path, and whether `jq` is installed. The other two are not, and the
    # difference is the criterion rather than convenience:
    #
    #   * the shim's presence in the project is a fact about a file THIS RUN WOULD WRITE, at Step 5,
    #     before it reaches the hook config. Asking it now would answer about the wrong tree, which
    #     is why the promise below names the ordering out loud instead;
    #   * whether `.codex/` can be CREATED is a question about a directory's mode, and the block's
    #     standing ruling on parent directories — the one S7 and 7h were written for — is that a
    #     write into a sealed parent is announced and then reported as declined, because the
    #     direction is safe and the alternative is a dry run that re-implements every `mkdir`.
    DRY_HOOKS_SKIP=""
    case "$PROJECT_DIR" in
      *\'*) DRY_HOOKS_SKIP="the project path contains a single quote, which --emit-config cannot escape" ;;
    esac
    if [ -z "$DRY_HOOKS_SKIP" ] && ! command -v jq >/dev/null 2>&1; then
      DRY_HOOKS_SKIP="jq is not on PATH, and every Kinglet hook needs it"
    fi
    if [ -n "$DRY_HOOKS_SKIP" ]; then
      printf '  .codex/hooks.json — %s, so it is NOT touched and no hook config is generated\n' \
        "$DRY_HOOKS_SKIP"
    elif [ -e "$PROJECT_DIR/.codex/hooks.json" ] && ! owned_by_installer '.codex/hooks.json' ''; then
      printf '  .codex/hooks.json exists and is not ours — would keep yours, and generate nothing\n'
    elif ! can_replace "$PROJECT_DIR/.codex/hooks.json"; then
      printf '  .codex/hooks.json is read-only — it is NOT touched; make it writable to have it regenerated\n'
    else
      printf '  .codex/hooks.json — generated from .claude/settings.json AFTER scripts/ is in place\n'
    fi
    if [ ! -f "$PROJECT_DIR/.codex/config.toml" ]; then
      printf '  .codex/config.toml (new — mcp_servers.UnityMCP -> http://localhost:8080/mcp)\n'
    elif grep -qF -- 'mcp_servers.UnityMCP' "$PROJECT_DIR/.codex/config.toml" 2>/dev/null; then
      printf '  .codex/config.toml already has a UnityMCP server — would leave alone\n'
    else
      printf '  .codex/config.toml exists without UnityMCP — would print the block, not rewrite\n'
    fi
    # THE HOME IS NAMED WHETHER OR NOT IT WILL BE WRITTEN, and the two states are different
    # sentences. A user reading a dry run before letting an installer near their home directory is
    # owed the answer to "does this touch anything outside my project", and "no" is an answer.
    if [ "$CODEX_TRUST" = yes ]; then
      printf '  %s/config.toml — OUTSIDE THIS PROJECT: would back it up and append one hook-trust table per hook\n' \
        "$CODEX_HOME_DIR"
    else
      printf '  %s/config.toml — not touched: hook trust is opt-in (--codex-trust), so the hooks would register and not run\n' \
        "$CODEX_HOME_DIR"
    fi
  else
    # THE OTHER HALF OF THE SAME QUESTION, AND THE ONE A USER ACTUALLY DRY-RUNS FOR. `claude` is the
    # DEFAULT client, so `install.sh --project-dir X --dry-run` against a project that already has a
    # Codex layer is a user asking "will this delete the layer I asked for?" — and until this arm
    # existed the block said nothing at all, while the real run printed two `info` lines and possibly
    # a `warn` block about it. That is exactly the announcement-vs-write divergence Step 3b's header
    # forbids, in the newest write.
    #
    # THE CONDITION IS STEP 8e's — the same FUNCTION, not a second spelling of it, which is the
    # whole point of `codex_layer_path` existing. The counts are derived from the same receipt Step
    # 8e reads, not from a second walk of the disk; `$RECEIPT` still holds the previous run's
    # receipt here, which is what makes the announcement able to answer at all.
    DRY_CX_KEEP=0; DRY_CX_GONE=0
    if [ "$MODE" = ours ] && [ -f "$RECEIPT" ]; then
      while IFS=$'\t' read -r dcx_rel _dcx_sha _dcx_mode _dcx_origin; do
        case "$dcx_rel" in ''|\#*|path) continue ;; esac
        codex_layer_path "$dcx_rel" || continue
        if [ -e "$PROJECT_DIR/$dcx_rel" ] || [ -L "$PROJECT_DIR/$dcx_rel" ]; then
          DRY_CX_KEEP=$((DRY_CX_KEEP + 1))
        else
          DRY_CX_GONE=$((DRY_CX_GONE + 1))
        fi
      done < "$RECEIPT"
    fi
    # NO PATH IN THE FIRST FIELD ON THE KEEP LINE, deliberately: tests/test-install-dryrun.sh's
    # parser reads the first field and would classify a leading `.agents/…` as a PROMISE about a
    # path this run does not write. `Codex layer` has neither a dot nor a slash, so it reads as
    # prose — the same device the `keep N file(s) you modified` lines above use.
    if [ "$DRY_CX_KEEP" -gt 0 ]; then
      printf '  Codex layer — %s receipted path(s) would be kept and re-recorded; this client writes none of them and removes none\n' \
        "$DRY_CX_KEEP"
    fi
    if [ "$DRY_CX_GONE" -gt 0 ]; then
      printf '  Codex layer — %s receipted path(s) are already gone from disk; their rows would be dropped (re-run with --client codex to restore)\n' \
        "$DRY_CX_GONE"
    fi
  fi

  printf '\nDry run complete — nothing written.\n'
  exit 0
fi

# ── Step 5: Install ──────────────────────────────────────────────────────────
# THE ONE `mv` IN THIS FILE THAT IS SUPPOSED TO END THE RUN, and it is stated here because every other
# one now reports and continues. If this rename fails, the next statements write the payload over the
# tree we have just failed to preserve; there is nothing to carry on with and nothing a `Not done:`
# entry could offer the user. `set -e` on a bare command is the correct outcome, and the receipt trap
# still writes what had been written. Its destination is also a path nothing else can hold — a fresh
# timestamped backup directory — so it is the only member of the class with no user file underneath it.
if [ -n "$BACKUP_DIR" ]; then
  mv "$CLAUDE_DIR" "$BACKUP_DIR"
  ok "Backed up existing .claude/ → $(basename "$BACKUP_DIR")"
fi

WRITTEN=0; KEPT=0
RECEIPT_TMP=$(mktemp)
# The canonical .mcp.json, written once at Step 8b and read twice: the create branch copies it out,
# and owned_by_installer compares against it. A second copy of that JSON — one to write, one to
# compare — is a second definition that drifts, which is the failure this whole change is about.
# Created here, beside RECEIPT_TMP, so both are set before the trap that removes them.
MCP_JSON_REF=$(mktemp)
# The same device for the Codex arm's .codex/config.toml: one canonical copy, written once and read
# twice — by the create branch and by owned_by_installer. Created here, unconditionally and beside
# the other two, so it is set before the trap that removes it: a `mktemp` inside the `if [ "$CLIENT"
# = codex ]` block below would be an unbound variable in the trap on every Claude Code run.
CODEX_CFG_REF=$(mktemp)

# ── The receipt, and why it is committed by a trap and not only at the end ────
#
# THE RECEIPT IS THE ONLY THING THAT MAKES AN INSTALL REVERSIBLE. uninstall.sh removes only the
# paths it lists, deliberately — a previous version deleted by filename and would remove files it
# had never installed. So a project with the payload on disk and NO receipt is a project the
# uninstaller refuses to touch ("Refusing to guess which files are ours"), permanently, and the only
# repair is by hand.
#
# EVERY STEP BETWEEN THE FIRST `cp` AND STEP 9 CAN END THE RUN. `set -euo pipefail` turns any
# unhandled non-zero status into an exit, and this file already carries two measurements of exactly
# that — a `return 3` injected into gitignore_plan (see Step 7) and a `return 1` injected into
# add_manifest_dependency (see its header) — both of which ended the run after the payload was
# written and before the receipt was. Neither is hypothetical: `cp "$MANIFEST" "$MANIFEST.bak"` in
# add_manifest_dependency dies on a DANGLING SYMLINK at Packages/manifest.json.bak, which a user can
# leave there by accident. `[ -e ]` is false through a dangling link, so the decline above it does
# not fire; cp reports `not writing through dangling symlink`; the run ends rc=1 with the whole
# payload installed and nothing to remove it. Measured on the tree this change lands on: 67 files
# under .claude/, an empty .claude/state/, and uninstall.sh exiting 1.
#
# SO THE COMMIT POINT MOVES TO THE TRAP RATHER THAN EARLIER IN THE FILE. Writing $RECEIPT early and
# rewriting it at the end was rejected: owned_by_installer reads $RECEIPT, and four call sites below
# depend on it still holding the PREVIOUS run's receipt (the comment above that function enumerates
# the four statements that keep it so). An early write would silently change what every one of those
# reads. The trap fires after all of them, so on the ordinary path nothing about this file's
# behaviour changes at all — Step 9 writes the receipt and sets RECEIPT_WRITTEN, and the trap then
# has nothing to do.
#
# WHAT THE PARTIAL RECEIPT CONTAINS IS WHAT IS ON DISK, not a guess. Every writer below appends its
# row to $RECEIPT_TMP immediately after the write it describes, so the rows present at any moment
# are the rows for the files written up to that moment. The one comment line naming the outcome is a
# `#` line, which every reader of this format already skips.
#
# AND IT IS NOT "ALWAYS WRITE A RECEIPT". `[ -s "$RECEIPT_TMP" ]` is load-bearing: MODE is decided
# by the receipt's ABSENCE, so a run that died having written nothing must leave nothing, or a
# foreign .claude/ — someone else's, arriving through a git clone — is read as ours on the next run.
# State O2 in tests/test-install-ownership.sh injects a die at this very line and asserts no receipt
# appears.
RECEIPT_WRITTEN=0
write_receipt() {
  local note="${1:-}"
  # The payload loop creates .claude/state a few lines down, so on an abort inside that loop the
  # directory does not exist yet and the redirect below would fail.
  mkdir -p "$(dirname "$RECEIPT")" 2>/dev/null || return 1
  {
    printf '# kinglet install receipt\n'
    printf '# edition: pioneer\n'
    printf '# Written by install.sh. uninstall.sh removes only what is listed here, and only if the\n'
    printf '# checksum still matches — so anything you edited or added is left alone.\n'
    printf '# toolkit-version: %s\n' "$TOOLKIT_VERSION"
    printf '# installed-at: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    [ -n "$BACKUP_DIR" ] && printf '# backup-dir: %s\n' "$(basename "$BACKUP_DIR")"
    [ -n "$note" ] && printf '# %s\n' "$note"
    printf 'path\tsha256\tmode\torigin\n'
    sort -t$'\t' -k1,1 "$RECEIPT_TMP"
  } > "$RECEIPT" || return 1
  RECEIPT_WRITTEN=1
  return 0
}

# `local rc=$?` FIRST, and nothing before it: the right-hand side is expanded before `local` runs,
# so this captures the status that triggered the trap. An EXIT trap that does not itself call `exit`
# leaves that status alone, which is why the interrupted run still reports the failure it had.
#
# `if write_receipt ...` rather than a bare call, because `set -e` is suspended inside a condition —
# a failed write here must not kill the shell a second time from inside its own exit handler.
receipt_rescue() {
  local rc=$?
  if [ "$RECEIPT_WRITTEN" -eq 0 ] && [ -s "$RECEIPT_TMP" ]; then
    if write_receipt "INCOMPLETE: install.sh exited $rc before it finished. The rows below cover what was written up to that point."; then
      err "This install did not finish (exit $rc). $RECEIPT_REL was written for what it had"
      err "already installed, so ./uninstall.sh can still remove it. Fix the cause and re-run."
    else
      err "This install did not finish (exit $rc) and $RECEIPT_REL could not be written."
      err "Remove .claude/ by hand if you want the project back as it was."
    fi
  fi
  rm -f "$RECEIPT_TMP" "$MCP_JSON_REF" "$CODEX_CFG_REF"
}
trap receipt_rescue EXIT

while IFS= read -r rel; do
  [ -n "$rel" ] || continue
  src="$SCRIPT_DIR/.claude/$rel"
  dest="$CLAUDE_DIR/$rel"
  if is_modified ".claude/$rel"; then
    KEPT=$((KEPT + 1))
    # Record the file as it now stands so the next run still recognises it.
    printf '.claude/%s\t%s\t%s\tuser-modified\n' "$rel" "$(sha_of "$dest")" "$(stat -c '%a' "$dest" 2>/dev/null || echo 644)" >> "$RECEIPT_TMP"
    continue
  fi
  mkdir -p "$(dirname "$dest")"
  cp "$src" "$dest"
  WRITTEN=$((WRITTEN + 1))
  printf '.claude/%s\t%s\t%s\ttoolkit\n' "$rel" "$(sha_of "$dest")" "$(stat -c '%a' "$dest" 2>/dev/null || echo 644)" >> "$RECEIPT_TMP"
done <<< "$PAYLOAD_FILES"

mkdir -p "$CLAUDE_DIR/state"
chmod +x "$CLAUDE_DIR/hooks/"*.sh 2>/dev/null || true

# The per-file provenance manifest is NOT shipped into user projects. It used to be, as
# .claude/provenance.tsv — 30 KB of maintenance evidence that nothing in a game project reads.
# Its actual job is to make a future ECU bump diffable rather than archaeological, and that bump
# happens in the kinglet-unity repository, not in the project the toolkit was installed into.
#
# It also rotted twice in two days once installed: the copy went stale the moment the toolkit's own
# manifest changed, and both times a reader believed it. A stale attribution manifest is worse than
# a link to a live one.
#
# The MIT obligation is unaffected and still met. The licence requires the copyright and permission
# notices to travel with the copies, which they do — .claude/NOTICE.md ships, carries both upstream
# licence texts in full, and points at the manifest in the repository for the per-file detail.

# Validation scripts ship alongside the payload. The test suite does not.
#
# check-provenance.sh was excluded first, with this reasoning: it validates the toolkit's own
# manifest, which is not shipped, so installing it would put a check in every project that can only
# ever report `err provenance.tsv not found` and exit 1 — and a permanently failing check trains
# people to ignore checks, which costs more than the script is worth.
#
# codex-probe.sh joined it on 2026-08-15, by the same reasoning plus one of its own. It measures
# THIS repository against Codex CLI: its default --out is docs/research/codex-client/evidence, which
# does not ship, and its prompts are Kinglet's own surfaces. A user project has nothing for it to
# measure. The reason of its own is that it copies ~/.codex/auth.json into a disposable CODEX_HOME —
# correct in a harness the toolkit's maintainers run deliberately, and not something to hand every
# installed project a copy of.
#
# codex-hook-shim.sh joined them on 2026-08-15 and LEFT AGAIN on 2026-08-16, which is the question
# that skip was holding open. Its reason had been that no agent, command or skill named it and
# nothing in a Claude Code session invokes it — true, and the wrong test, because the reader it
# exists for is not in a Claude Code session. The Codex ship list settled it: the hook config
# `--emit-config` writes carries an ABSOLUTE path to this script, so it has to be in the project
# it points into. A shim excluded from the payload is a `.codex/hooks.json` pointing at a file that
# is not there, which under Codex is not an error — it is nine registered hooks that enforce
# nothing. It now ships, and `.claude/commands/unity-doctor.md` names it — one surface, not two;
# this comment claimed `.claude/skills/using-kinglet/SKILL.md` named it as well, which was true of a
# draft that was reverted whole and never true of the tree. The reachability rule is satisfied by
# that one citation rather than waived. codex-command-to-skill.sh ships for the same reason and was
# never skipped: Codex has no command surface, so Kinglet's commands only reach a Codex reader as
# generated skills, and the doctor command names it too.
#
# Both remaining skips use the identical one-name-per-line comparison form on
# purpose: tests/test-derived-counts.sh and tests/test-shipped-citations.sh both extract the skipped
# names from these lines by matching that exact shape, and derive the installed-script set from
# them — so a skip written any other way (a `case` list, a loop over an array) would make those
# derivations silently disagree with this loop. This sentence deliberately does not quote the shape
# it is describing: the extractor is a plain grep over this whole file, and a comment that spells
# the pattern out is itself extracted, which is how a third "skipped script" named `NAME` appeared
# in the count on the first attempt at this paragraph.
#
# Measured 2026-08-04: that argument was applied to one script and not to the class it describes.
# Running the shipped suite in a real installed project gives **143 failures out of 229 assertions**,
# and it always has. Two independent causes:
#
#   1. run-tests.sh computes REPO_DIR as the parent of tests/. In this repository that is the repo
#      root; in an installed project it is `.claude/`, so every path is off by one level and the
#      tests look for `.claude/.claude/hooks/...`.
#   2. A large share of the test files reference install.sh, provenance.tsv, tests/fixtures/,
#      migration/baseline-inventory.json or tools.kinglet_build — none of which ship. Those cannot
#      pass in a project whatever REPO_DIR says.
#
#      Derive that share; do not trust a number written here. This sentence carried a hardcoded pair,
#      "twelve of the twenty-eight", and was wrong at both ends on both later measurements: 15 of 30
#      at 076464b and 16 of 31 on 2026-08-12. The set is the claim, so the commands are the claim:
#        grep -lE 'install\.sh|provenance\.tsv|tests/fixtures/|migration/baseline-inventory\.json|tools\.kinglet_build' tests/test-*.sh | wc -l
#        ls tests/test-*.sh | wc -l
#
# The suite validates the toolkit, not the project. What a user actually needs is
# scripts/studio-doctor.sh, which does ship, runs correctly against an installed layout, and checks
# the things that matter there: the install verified against its receipt, every hook named by
# settings.json present, the MCP bridge configured, the Input System package present.
#
# So: scripts/ ships, tests/ does not. An installed project that already has .claude/tests/ from an
# earlier version gets it removed by the payload-prune above, which is the behaviour that exists for
# exactly this.
# This loop is the payload loop's twin and must stay its twin. It did not: the payload loop tested
# is_modified before writing, and this one's `cp` was unconditional with a `toolkit` row regardless.
# So a user who edited .claude/scripts/studio-doctor.sh got, in ONE run:
#
#   warn 1 installed file(s) have local edits — keeping yours:
#          .claude/scripts/studio-doctor.sh
#   ok   Installed N file(s).
#
# N is the whole payload — the point is that the kept file is inside it. It read `85` until
# 2026-08-13, a real figure from the day it was measured and stale by one the moment
# scripts/detect-pipeline.sh joined the group loop, at which point it read as a current transcript of
# a run that no longer happens. `bash install.sh --project-dir <fixture> --yes` prints the live one.
#
# and the edit was gone. MODIFIED_FILES is computed at Step 4, before either loop runs, so the
# warning was accurate about what the installer knew and false about what it then did — the one
# failure worse than silent data loss, because the user is told the file is safe in the same breath.
# Measured on a fixture 2026-08-12; tests/test-install-ownership.sh's state H holds all four
# directions of it, including the one that stops the fix becoming "keep everything".
#
# The path form is load-bearing and is not a coincidence: MODIFIED_FILES is built from receipt
# field 1, these rows are written as `.claude/scripts/<name>`, and is_modified matches whole lines
# (`grep -qxF`). Change either form and the test below silently never matches — a no-op that reads
# as a fix.
# shellcheck disable=SC2043
# One group today, and deliberately a list — same seam as the NEW_PATHS loop above.
for group in scripts; do
  [ -d "$SCRIPT_DIR/$group" ] || continue
  mkdir -p "$CLAUDE_DIR/$group"
  for f in "$SCRIPT_DIR/$group"/*.sh; do
    [ -f "$f" ] || continue
    b=$(basename "$f")
    [ "$b" = "check-provenance.sh" ] && continue
    [ "$b" = "codex-probe.sh" ] && continue
    dest="$CLAUDE_DIR/$group/$b"
    if is_modified ".claude/$group/$b"; then
      # Kept, so counted as kept: WRITTEN and KEPT both appear in the summary line, and a kept file
      # counted as written is a write the run did not make. Recorded as the file now stands, so the
      # NEXT install still recognises it — the same reason the payload loop records the edited sha.
      KEPT=$((KEPT + 1))
      printf '.claude/%s/%s\t%s\t%s\tuser-modified\n' "$group" "$b" "$(sha_of "$dest")" "$(stat -c '%a' "$dest" 2>/dev/null || echo 755)" >> "$RECEIPT_TMP"
      continue
    fi
    cp "$f" "$dest"
    chmod +x "$dest"
    printf '.claude/%s/%s\t%s\t%s\ttoolkit\n' "$group" "$b" "$(sha_of "$dest")" "755" >> "$RECEIPT_TMP"
    WRITTEN=$((WRITTEN + 1))
  done
done

# Remove what the previous install owned and this payload dropped. Computed before any write, so a
# path this run creates can never appear here. Files the user edited were filtered out already.
REMOVED=0
if [ "$ORPHAN_COUNT" -gt 0 ]; then
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    rm -f "$PROJECT_DIR/$rel" && REMOVED=$((REMOVED + 1))
  done <<< "$ORPHANS"
  # Skill directories are one level deep, but not always a single file — subagent-driven-implementation
  # ships four sibling prompt templates alongside SKILL.md. Either way, once every file this run
  # tracked is gone the directory is an empty shell that still reads as a skill to anyone listing the
  # tree.
  find "$CLAUDE_DIR" -mindepth 1 -type d -empty -delete 2>/dev/null || true
  ok "Removed $REMOVED file(s) no longer in the payload."
fi
if [ "$ORPHAN_KEPT_COUNT" -gt 0 ]; then
  warn "$ORPHAN_KEPT_COUNT file(s) dropped from the payload have your edits — left in place:"
  printf '%s' "$ORPHANS_KEPT" | while IFS= read -r o; do [ -n "$o" ] && printf '       %s\n' "$o"; done
  # THE ABANDONED WORK HERE IS THE REMOVAL, NOT THE FILE — which is why this is in the block while
  # `keeping yours` is not. Keeping the edited bytes is right; what did not happen is the retirement
  # this payload asked for, and the comment on the ORPHANS scan above states the cost in the words
  # that matter: "An upgrade that leaves a deleted agent reachable is worse than no upgrade: the
  # model still sees it."
  note_not_done "$ORPHAN_KEPT_COUNT retired surface(s) listed above were NOT removed — this payload no longer ships them, but you edited them, so they stay on disk and stay selectable by the model. Delete them yourself once you have salvaged the edits."
fi

# A kept settings.json is the one file whose staleness is silent and total.
#
# settings.json is the most-edited file in the payload — it is where you disable a plugin or widen a
# permission — so on any real project it is "yours" and we keep it, correctly. But it is also the
# only place a hook is registered. A payload that ships a NEW hook therefore lands the script on disk
# and registers nothing: the hook never fires, and nothing reports that. Measured on a real project,
# where the hook carrying the whole process chain arrived unregistered and silent.
#
# Merging someone's JSON is not something an installer should do unasked, so this reports instead.
if is_modified ".claude/settings.json" && [ -f "$CLAUDE_DIR/settings.json" ]; then
  UNREG=""
  while IFS= read -r h; do
    [ -n "$h" ] || continue
    grep -qF -- "$h" "$CLAUDE_DIR/settings.json" || UNREG="${UNREG}${h}"$'\n'
  done < <(grep -oE '\.claude/hooks/[a-z_-]+\.sh' "$SCRIPT_DIR/.claude/settings.json" | sort -u)
  UNREG_COUNT=$(printf '%s' "$UNREG" | grep -c . || true)
  if [ "$UNREG_COUNT" -gt 0 ]; then
    warn "Your settings.json was kept, so $UNREG_COUNT hook(s) this version ships are NOT registered:"
    printf '%s' "$UNREG" | while IFS= read -r h; do [ -n "$h" ] && printf '       %s\n' "$h"; done
    warn "They are on disk but will never fire. Add them to \"hooks\" in .claude/settings.json,"
    warn "or diff yours against $SCRIPT_DIR/.claude/settings.json."
    # THE KEPT FILE IS NOT THE ABANDONED WORK; THE REGISTRATION IS. settings.json itself landed and
    # is the user's, exactly as the ownership rule intends — but a second artifact, the hook scripts
    # this version ships, is on disk and inert, and no amount of reading settings.json tells you so.
    # That is the boundary this block draws between a keep that belongs here and one that does not.
    note_not_done "$UNREG_COUNT hook(s) listed above are installed but NOT registered — your .claude/settings.json was kept, and it is the only place a hook is registered, so they will never fire. Add them to \"hooks\" there, or diff yours against $SCRIPT_DIR/.claude/settings.json."
  fi

  # THE OTHER DIRECTION, WHICH A PAYLOAD THAT SHRANK CREATES AND NOTHING ASKED.
  #
  # The scan above asks one question — "we ship this hook, is it registered?" — and a payload that
  # only ever GREW is fully described by it. The 2026-08-03 and 2026-08-13 cuts made the reverse
  # question real: "your file registers this, is it still there?" Step 5's prune deletes a retired
  # hook's script because it is ours and untouched, while the entry naming it lives in the
  # settings.json this run just kept, so the entry survives the removal and points at nothing.
  # Claude Code does not report a hook command it cannot find. That is the same silence an
  # unregistered hook on disk gets, arriving from the opposite side, and it does not self-heal: the
  # kept file is kept again on every subsequent run. Measured on an upgrade across the 2026-08-13
  # cut — 27 registrations in the kept file over 12 hooks on disk, 15 of them naming deleted files,
  # with `Hooks 27` printed under `Installation complete.`
  #
  # EXISTENCE ON DISK, NOT ABSENCE FROM THE PAYLOAD, is the test. It is the condition that actually
  # costs something, it needs no second file to be read, and it also catches a registration typed by
  # hand at a path that never existed — which the payload comparison would call correct.
  #
  # WARN, DO NOT EDIT. The file was kept because it is the user's, and an installer that silently
  # rewrites the file it has just finished reporting as preserved is a worse defect than this one.
  # Which entry, under which matcher, under which event is a JSON-shaped question besides, and the
  # comment above already rules that merging someone's JSON unasked is not an installer's business.
  DEAD_REG=""
  while IFS= read -r h; do
    [ -n "$h" ] || continue
    [ -f "$PROJECT_DIR/$h" ] || DEAD_REG="${DEAD_REG}${h}"$'\n'
  done < <(grep -oE '\.claude/hooks/[a-z_-]+\.sh' "$CLAUDE_DIR/settings.json" | sort -u)
  DEAD_REG_COUNT=$(printf '%s' "$DEAD_REG" | grep -c . || true)
  if [ "$DEAD_REG_COUNT" -gt 0 ]; then
    warn "Your settings.json was kept, so $DEAD_REG_COUNT hook registration(s) name files that are not there:"
    printf '%s' "$DEAD_REG" | while IFS= read -r h; do [ -n "$h" ] && printf '       %s\n' "$h"; done
    warn "This version does not ship them. Remove their entries from \"hooks\" in .claude/settings.json,"
    warn "or diff yours against $SCRIPT_DIR/.claude/settings.json."
    # SAME BOUNDARY AS THE BLOCK ABOVE, READ FROM THE OTHER END. What was abandoned is not the kept
    # file — that is the user's and landing it is correct — but the RETIREMENT this payload asked
    # for, which finished on disk and stopped at the registration. The `ORPHAN_KEPT` note a few
    # steps up states the same thing about a retired surface's file; this states it about a retired
    # surface's last remaining reference.
    note_not_done "$DEAD_REG_COUNT hook registration(s) listed above were NOT removed — your .claude/settings.json was kept, this version no longer ships those hooks, and the entries naming them outlived the files. Delete them from \"hooks\" there, or diff yours against $SCRIPT_DIR/.claude/settings.json."
  fi
fi

ok "Installed $WRITTEN file(s)$([ "$KEPT" -gt 0 ] && printf ', kept %s of yours' "$KEPT")."

# ── Step 6: CLAUDE.md ────────────────────────────────────────────────────────
# The installer owns the destination; the generator only writes to stdout. Upstream had both
# writing the same path, which corrupted fresh files and destroyed existing ones.
CLAUDE_MD="$PROJECT_DIR/CLAUDE.md"

# ── Process provider — detect, propose, never assume ────────────────────────
# The platform design requires that Kinglet propose a detected provider and the
# user approve it, and that Kinglet never copy, disable, or shadow it. Detection
# is read-only and re-run on every install: if the provider is uninstalled later,
# the next refresh drops the sentence, which is the correct behaviour.
#
# What that reasoning did NOT cover: a refresh where nothing changed except the
# tty. PROVIDER_CHOICE was set only on the interactive branch, so `--yes` or a
# pipe took "the safe default (no declaration)" even for a provider that is still
# installed and that the user already approved. emit_provider_verdict lives inside
# the marked region, so the --facts-only refresh regenerated that region without
# the sentence and deleted it. studio-doctor.sh tells the user to "Re-run
# install.sh to refresh the declaration" — in CI or with --yes, that revoked it.
#
# So read the existing declaration first. Same parse shape as studio-doctor.sh's
# staleness check, deliberately: one grammar for one section, not two.
EXISTING_PROVIDER=""
if [ -f "$CLAUDE_MD" ] && grep -q '^### Process provider' "$CLAUDE_MD"; then
  EXISTING_PROVIDER=$(awk '/^### Process provider/{f=1} f && /owned by/{
      if (match($0, /`[^`]+`/)) print substr($0, RSTART+1, RLENGTH-2); exit }' "$CLAUDE_MD")
fi

if [ -f "$CLAUDE_USER_SETTINGS" ] \
   && grep -q '"superpowers@claude-plugins-official"[[:space:]]*:[[:space:]]*true' "$CLAUDE_USER_SETTINGS"; then
  if [ "$ASSUME_YES" -eq 1 ] || [ ! -t 0 ]; then
    if [ "$EXISTING_PROVIDER" = superpowers ]; then
      # Approved before, still installed, nothing to re-decide. Carrying it
      # forward is the conservative act here; dropping it is the change.
      PROVIDER_CHOICE="superpowers"
      info "Superpowers detected and already declared in CLAUDE.md — declaration carried forward."
    else
      # The safe default is no declaration: it changes nothing about how the
      # project behaves today.
      info "Superpowers detected; --yes takes the safe default (no provider declaration)."
    fi
  elif [ "$EXISTING_PROVIDER" = superpowers ]; then
    echo "  Superpowers is installed and this project already declares it as its"
    echo "  discovery and planning provider."
    read -rp "  Keep the declaration? [Y/n]: " REPLY_PROVIDER
    case "$REPLY_PROVIDER" in [nN]*) ;; *) PROVIDER_CHOICE="superpowers" ;; esac
  else
    echo "  Superpowers is installed for your user account."
    echo "  Kinglet can record it as this project's discovery and planning provider."
    echo "  This writes one sentence into CLAUDE.md. It does not modify Superpowers"
    echo "  or your global settings."
    read -rp "  Record it? [y/N]: " REPLY_PROVIDER
    case "$REPLY_PROVIDER" in [yY]*) PROVIDER_CHOICE="superpowers" ;; esac
  fi
fi

# Array, not the bare `${PROVIDER_CHOICE:+--provider "$PROVIDER_CHOICE"}` idiom: unquoted
# that is subject to word splitting, and under `set -u` in bash 3.2 an empty array needs
# the `+` guard below or expansion itself errors when PROVIDER_CHOICE was never set.
GEN_ARGS=()
[ -n "$PROVIDER_CHOICE" ] && GEN_ARGS+=(--provider "$PROVIDER_CHOICE")

GEN="$SCRIPT_DIR/scripts/generate-claude-md.sh"
# Tracks which branch below actually ran, so the "Next steps" summary can name the file it really
# touched instead of assuming CLAUDE.md was (re)written. See defect 9: the installer already knows
# this — it just wasn't asked.
CLAUDE_MD_BRANCH="skipped"
# The same predicate the dry run announced from, called rather than restated — see Step 3b. It is
# read ONCE, here, and every arm below keys off the token: two calls could disagree only if
# something between them rewrote the file, and the arms are what rewrite the file.
CLAUDE_MD_MARKER_STATE="$(marked_region_state "$CLAUDE_MD")"
if [ -f "$GEN" ]; then
  # BESIDE THE DESTINATION, SO THE RENAMES BELOW ARE RENAMES. Every use of this temp ends in a `mv`
  # into $PROJECT_DIR — CLAUDE.md, CLAUDE.md.generated, and (as `merge_marked_region`'s facts file)
  # the merge — and `mv` is `rename(2)` only within one filesystem. From `$TMPDIR` on a host where
  # `/tmp` is a tmpfs, or where the project lives on a second drive, every one of those degraded to
  # a copy that can be interrupted half-way, leaving a truncated entry document at the project root
  # while the run reports that nothing was touched. See `mktemp_beside`.
  TMP_MD=$(mktemp_beside "$PROJECT_DIR" .kinglet-claude-md)
  if [ "$CLAUDE_MD_MARKER_STATE" = absent ]; then
    if bash "$GEN" ${GEN_ARGS[@]+"${GEN_ARGS[@]}"} "$PROJECT_DIR" > "$TMP_MD" 2>/dev/null; then
      # THE STATUS IS READ HERE TOO, and it was a bare `mv` until 2026-08-17. This arm needs no
      # `can_replace` — it is reached only when `marked_region_state` said `absent`, so there is no
      # regular file at that path to be read-only — but the RENAME can still fail: measured (W2) in a
      # project directory at 555, `mv` failed and `set -e` ended the run at `exit 1` with the payload
      # already written and no CLAUDE.md. `skipped` is the honest branch for it: the file did not
      # exist before this arm and does not exist after it, which is exactly what that entry says.
      if mv "$TMP_MD" "$CLAUDE_MD"; then
        ok "Generated CLAUDE.md"
        CLAUDE_MD_BRANCH="new"
      else
        rm -f "$TMP_MD"
        warn "CLAUDE.md could not be written — the rename into place failed, so nothing was generated."
      fi
    else
      rm -f "$TMP_MD"; warn "CLAUDE.md generation failed — skipped."
    fi
  elif [ "$CLAUDE_MD_MARKER_STATE" = wellformed ]; then
    # Refresh only the fenced block; everything the user wrote stays byte-for-byte.
    #
    # THE CONDITION IS THE PAIR, NOT THE OPENING MARKER. `grep -q ...begin` stood here and let a file
    # with no closing marker into this arm, where the awk below silently deleted every line under the
    # region and then said `your prose untouched`. Step 3b's predicate holds the reasoning and the
    # measurements; the malformed arm below is where such a file goes now.
    if bash "$GEN" --facts-only ${GEN_ARGS[@]+"${GEN_ARGS[@]}"} "$PROJECT_DIR" > "$TMP_MD" 2>/dev/null; then
      # The generator owns every byte between the markers, heading included. This used to print the
      # "## Project Facts" heading here as well, from the era when --facts-only emitted only the
      # table. That was corrected in generate-claude-md.sh — on one side. The result was a second,
      # empty heading appearing on every refresh, compounding once per install; a real project was
      # found carrying two. Two producers for one region is the bug the generator's own comment
      # warns about, so this side prints nothing of its own.
      #
      # THE `end` RULE USED TO OPEN `print ""` AND THAT WAS THE SAME BUG, ONE BLANK LINE WIDE. The
      # generator's emit_marked_region already ends in a blank line, and the fresh-file arm writes
      # begin + that region + end with nothing added — so the refresh arm emitted the region one line
      # LONGER than the arm it is supposed to reproduce. Measured on a urp fixture: 54 region lines on
      # install 1, 55 from install 2 on, `cmp`-clean between runs 2/3 and 3/4 and prose outside
      # byte-identical, so it was bounded rather than compounding. It was still a byte of the user's
      # file that no run asked to change, and the first /unity-init after a refresh install normalised
      # it away as a one-line `git diff` nobody requested. The rule now prints the end marker alone.
      #
      # THE MERGE ITSELF MOVED OUT OF THIS ARM ON 2026-08-17, unchanged, because `AGENTS.md` needed the
      # same four lines and two copies of a merge over two generated files is how this branch's other
      # paired readers drifted. Both callers are in this file, so there is one definition and no
      # comparison guard to keep two of them honest.
      #
      # THE STATUS IS READ, AND `2` GETS ITS OWN SENTENCE. A read-only CLAUDE.md is the state a
      # Perforce project is in whenever the file is not checked out, and `refresh failed` is not what
      # that user needs to hear — the action is theirs and it is one command. See the function's
      # header for the measurement that made this three outcomes rather than two.
      MERGE_RC=0
      merge_marked_region "$CLAUDE_MD" "$TMP_MD" || MERGE_RC=$?
      if [ "$MERGE_RC" -eq 0 ]; then
        ok "Refreshed the generated section of CLAUDE.md (your prose untouched)"
        CLAUDE_MD_BRANCH="refreshed"
      elif [ "$MERGE_RC" -eq 2 ]; then
        warn "CLAUDE.md is read-only, so its generated section was NOT refreshed and nothing was written."
        warn "Make it writable (under Perforce: check it out) and re-run install.sh."
        CLAUDE_MD_BRANCH="refresh-failed"
        note_not_done "CLAUDE.md — the file is read-only, so its generated block was NOT refreshed and still carries an earlier run's project facts. Your own prose was not touched. Make it writable (under Perforce: check it out) and re-run install.sh."
      else
        warn "CLAUDE.md refresh failed — left as-is."
        CLAUDE_MD_BRANCH="refresh-failed"
        note_not_done "CLAUDE.md — the generated block could not be refreshed, so it still carries an earlier run's project facts. Your own prose was not touched. The warn line above says at which step it failed."
      fi
      rm -f "$TMP_MD"
    else
      rm -f "$TMP_MD"
      warn "CLAUDE.md refresh failed — left as-is."
      # THE `skipped` ENTRY IS THE WRONG SENTENCE FOR THIS PATH AND WAS PRINTED ON IT UNTIL 2026-08-17.
      # It reads "not generated, so this project has no toolkit configuration file and the FILL:
      # markers never landed" — every clause false of a project whose CLAUDE.md exists, carries the
      # markers, and simply did not get this run's facts. A refresh that fails is a STALE block, not an
      # absent one, and the two need different sentences because they need different actions.
      CLAUDE_MD_BRANCH="refresh-failed"
      note_not_done "CLAUDE.md — the generated block could not be refreshed, so it still carries an earlier run's project facts. Your own prose was not touched. The warn line above says at which step it failed."
    fi
  elif [ "$CLAUDE_MD_MARKER_STATE" != none ]; then
    # DECLINE, DO NOT REPAIR. This file has kinglet:generated markers, so it is not the marker-less
    # case below; and it does not have a pair this installer can bound, so it is not the refresh case
    # above.
    #
    # THE REPAIR THAT LOOKS OBVIOUS IS "CLEAR `skip` AT EOF", AND IT HAS TWO READINGS. BOTH WERE
    # BUILT AND RUN; NEITHER IS A REPAIR.
    #
    #   * Literally — `END { skip = 0 }` — it is a NO-OP. awk's END block runs after the last line,
    #     so there is nothing left for the flag to gate. Measured: the begin-only file still
    #     amputates to 80 lines / 2746 bytes and the swapped file still walks 84f3ba1d -> 1c804997,
    #     shas identical to the unrepaired installer. It fixes zero states, not one.
    #   * Effectively — buffer the skipped lines and flush them at END when no end marker ever
    #     arrived — it does save the user's prose, in BOTH malformed states. What it does instead is
    #     promote the old region into that prose and re-emit the facts block on every run: begin-only
    #     goes 124 -> 176 -> 228 lines with `## Project Facts` headings at 10 -> 11 -> 12, swapped
    #     goes 125 -> 178 -> 231. It never converges, it never repairs the pair that caused it, and
    #     it goes on printing `your prose untouched` while doing it.
    #
    # So the ground for declining is not "the repair still destroys work" — the second reading does
    # not. It is that the repair is NON-CONVERGENT and permanently reinterprets toolkit-owned bytes
    # as the user's prose: content this installer wrote inside its own markers becomes content it
    # must never touch again, growing once per install, with the malformed pair still there.
    # Declining leaves the file exactly as the user left it and names the one edit that ends the
    # state.
    #
    # NOTHING IS WRITTEN — not CLAUDE.md, not CLAUDE.md.generated. The second is deliberate: this
    # user's file already carries markers, so the beside-yours remedy ("paste the kinglet:generated
    # markers into your CLAUDE.md") is advice that would give them a second stray marker. The remedy
    # here is to repair the pair, and that is what the entry says.
    rm -f "$TMP_MD"
    warn "CLAUDE.md — $(marked_region_problem "$CLAUDE_MD_MARKER_STATE"), so it was NOT touched."
    warn "Nothing was merged into it and nothing was generated beside it."
    warn "$(marked_region_remedy "$CLAUDE_MD_MARKER_STATE" CLAUDE.md install.sh)"
    CLAUDE_MD_BRANCH="malformed"
  else
    # ASK BEFORE WRITING. The `mv` below used to be unconditional, and this is the arm where that
    # cost the user work — twice over, on two different fixtures:
    #
    #   * The installer's own summary says "Fill in the FILL: markers in CLAUDE.md.generated". A user
    #     who does that and reinstalls got the nine unfilled markers back. The edit survived ZERO
    #     reinstalls, and once Task 2b gave the file a receipt row, run 2 printed
    #     `keeping yours: CLAUDE.md.generated` four lines before destroying it.
    #   * A user who wrote their own CLAUDE.md.generated and had never run this installer lost it on
    #     the first install ever — and the row below then recorded the replacement as `toolkit`, so
    #     uninstall.sh would take what was left.
    #
    # The condition is a disjunction, not `owned_by_installer` alone: that helper opens with
    # `[ -f "$abs" ] || return 1`, so on the ordinary case — nothing at that path yet — it correctly
    # answers "not ours" and a bare call would decline every fresh install. Absence is the case where
    # there is nothing to lose.
    #
    # `-e`, not `-f`: a directory or a symlink at that path is not ours to clobber either, and `mv`
    # onto a directory moves the file INSIDE it rather than replacing it.
    #
    # There is no reference copy to pass — this file is generated per project from that project's
    # Unity version, packages and provider — so the ref argument is '' and owned_by_installer's first
    # arm is skipped by construction. What answers is the previous receipt, and it is a checksum
    # comparison, so the file we wrote last run is ours and the same file after the user edits it is
    # not. See the row below for the rest of that reasoning.
    if [ -e "$PROJECT_DIR/CLAUDE.md.generated" ] && ! owned_by_installer 'CLAUDE.md.generated' ''; then
      rm -f "$TMP_MD"
      warn "CLAUDE.md.generated exists and is not ours — keeping yours, untouched."
      warn "No generated file was produced this run. Rename or delete CLAUDE.md.generated and"
      warn "re-run to get one."
      # NOT `separate`. That value is the row predicate's first disjunct, and setting it here would
      # write a receipt row claiming a file this branch just refused to write — the same defect
      # pointing the other way, with uninstall.sh deleting the user's file instead of the installer.
      # It also drives the Next-steps summary, which would otherwise send the user to FILL: markers
      # in a file that does not contain any.
      CLAUDE_MD_BRANCH="kept-yours"
    elif ! can_replace "$PROJECT_DIR/CLAUDE.md.generated"; then
      # THE THIRD DOOR ON THE SAME CONDITION. This arm's `mv` lands on an existing
      # CLAUDE.md.generated whenever a previous run wrote one, and a read-only file there prompts and
      # then kills the install exactly as the AGENTS.md write arm did — see `can_replace`. Declining
      # keeps the rest of the run alive and names the one action that clears it.
      #
      # ITS OWN BRANCH VALUE, AND THE FIRST VERSION OF THIS ARM BORROWED `kept-yours`. That token's
      # entry reads *"CLAUDE.md.generated — yours was kept untouched, so no generated file was
      # produced this run. Rename or delete it and re-run to get one."* Every clause is false here:
      # the file is OURS (this arm is reached only after `owned_by_installer` failed to disown it),
      # nothing was kept because the user chose it, and the remedy contradicts the `warn` line two
      # lines above it — renaming or deleting a read-only file is not the action, making it writable
      # is. That is the same defect this commit's sibling fixed for `skipped`, in the same commit,
      # one arm over.
      rm -f "$TMP_MD"
      warn "CLAUDE.md.generated is read-only, so nothing was written beside your CLAUDE.md."
      warn "Make it writable (under Perforce: check it out) and re-run install.sh."
      CLAUDE_MD_BRANCH="generated-not-written"
      note_not_done "CLAUDE.md.generated — the file is read-only, so this run wrote nothing beside your CLAUDE.md and it still holds an earlier run's content. Your own CLAUDE.md was not touched. Make it writable (under Perforce: check it out) and re-run install.sh."
    elif bash "$GEN" ${GEN_ARGS[@]+"${GEN_ARGS[@]}"} "$PROJECT_DIR" > "$TMP_MD" 2>/dev/null; then
      # The status, for the reason the fresh arm above reads it: `can_replace` cannot see a rename
      # that fails on the directory rather than on the file.
      if mv "$TMP_MD" "$PROJECT_DIR/CLAUDE.md.generated"; then
        warn "CLAUDE.md exists and has no generated markers — wrote CLAUDE.md.generated instead."
        warn "Yours was not touched. Merge by hand, or add the markers to let us refresh in place."
        CLAUDE_MD_BRANCH="separate"
      else
        rm -f "$TMP_MD"
        warn "CLAUDE.md.generated could not be written — the rename into place failed."
        warn "Your own CLAUDE.md was not touched."
        CLAUDE_MD_BRANCH="generated-not-written"
        note_not_done "CLAUDE.md.generated — the rename into place failed, so this run wrote nothing beside your CLAUDE.md and none of the toolkit's configuration reached this project. Your own CLAUDE.md was not touched."
      fi
    else
      rm -f "$TMP_MD"; warn "CLAUDE.md generation failed — skipped."
    fi
  fi
else
  # THE SUMMARY'S `*)` ARM ALREADY SAID "see the warning above" ON THIS PATH, AND THERE WAS NO
  # WARNING ABOVE. Measured on a scratch toolkit with the generator removed: the only line in the
  # whole run mentioning CLAUDE.md was `2. CLAUDE.md generation was skipped — see the warning
  # above.` — a summary pointing at output that was never printed, on the one path where the file
  # the toolkit's entire configuration lives in does not exist at all.
  warn "$GEN not found — CLAUDE.md was not generated."
fi

# ONE RECORDING POINT PER OUTCOME, KEYED ON THE VALUE THE BRANCHES ALREADY SET. `skipped` is reached
# several arms — the generator is absent, or it failed on the fresh-file arm or the beside-yours arm,
# or the fresh arm's rename into place failed —
# and each of those printed its own warn line naming which. Restating that here would be a second copy
# of a decision made above, so the entry points at the warning instead and the `else` branch above
# exists to guarantee there is one.
#
# THE REFRESH ARM USED TO LAND HERE TOO AND ITS SENTENCE WAS FALSE OF IT. `skipped` says the file was
# "not generated … and the FILL: markers never landed"; a failed refresh leaves a CLAUDE.md that
# exists, carries the markers, and has last run's facts in it. It sets `refresh-failed` and records
# its own entry at the site, where the reason — read-only, or a merge that could not be written — is
# still in hand. Recorded 2026-08-17, with the read-only path.
#
# `separate` IS HERE, AND THIS COMMENT ARGUED THE OPPOSITE FOR ONE ROUND. It read: "that arm writes
# CLAUDE.md.generated, announces it, and the Next-steps line names it. Work done differently is not
# work abandoned." Two things are wrong with that.
#
# THE FIRST IS THAT IT INVENTS A CRITERION TO ESCAPE THE STATED ONE. The criterion in this file's own
# header is "absent or INERT", and CLAUDE.md.generated on this branch is inert in exactly the sense an
# unregistered hook is: on disk, doing nothing, until the user acts. Claude Code reads CLAUDE.md.
# Until the block is merged into it, not one line of the toolkit's configuration applies — measured on
# a urp fixture whose CLAUDE.md is the user's own: rc=0, no block, and `grep -c kinglet:generated
# CLAUDE.md` is 0. A caller running the snippet MCP-SETUP.md prints got a clean pass on that project.
#
# THE SECOND IS THAT IT IS NOT A KEEP AT ALL. The header's exemption is for a file kept because the
# user edited it; here the installer WROTE a file, to a path the user must act on. And every project
# that already has a CLAUDE.md takes this branch, which is most projects that are not new.
#
# THE ALTERNATIVE WAS TO NAME `separate` IN MCP-SETUP.md AS A SECOND STATED EXCEPTION beside
# --dry-run, and it was rejected: an exception at the one outcome a scripted caller most needs to
# hear about is a contract nobody can script against. This entry is also SELF-CLEARING — the moment
# the user takes its advice and adds the markers, the branch becomes `refreshed` and the entry stops —
# which is the shape a recurring entry has to have to be worth printing.
#
# `malformed` IS HERE ON EXACTLY THE STATED CRITERION AND NOT ON A NEW ONE. The refresh this run was
# asked for did not happen and no second artifact was written in its place, so the toolkit's project
# facts are ABSENT from the only file Claude Code reads — the header's first clause, not the
# edited-file exemption, which does not apply because the user chose nothing here: an unclosed marker
# pair is what a half-finished hand-merge or a bad conflict resolution leaves behind. It is
# self-clearing in the same way `separate` is: repair the pair and the next run is `refreshed`.
case "$CLAUDE_MD_BRANCH" in
  skipped)
    note_not_done "CLAUDE.md — not generated, so this project has no toolkit configuration file and the FILL: markers never landed. The warn line above says how it failed; re-run install.sh once that is fixed."
    ;;
  # `refresh-failed` and `generated-not-written` record at their own sites, where the reason is still
  # in hand — see the header above.
  refresh-failed|generated-not-written)
    ;;
  kept-yours)
    note_not_done "CLAUDE.md.generated — yours was kept untouched, so no generated file was produced this run. Rename or delete it and re-run to get one."
    ;;
  separate)
    note_not_done "CLAUDE.md — yours has no generated markers, so the toolkit's configuration went to CLAUDE.md.generated beside it. Claude Code reads CLAUDE.md: none of it applies until you merge that block in, or paste the kinglet:generated markers into your CLAUDE.md and re-run to have it refreshed in place."
    ;;
  malformed)
    note_not_done "CLAUDE.md — $(marked_region_problem "$CLAUDE_MD_MARKER_STATE"), so the generated block was NOT refreshed and your file was left exactly as it was. $(marked_region_remedy "$CLAUDE_MD_MARKER_STATE" CLAUDE.md install.sh)"
    ;;
esac

# CLAUDE.md.generated is the second file this installer creates, keeps, announces — and, until
# 2026-08-13, never recorded. Same defect as Packages/manifest.json.bak one step earlier, on the
# project root where the user sees it: written by the `separate` branch above, pointed at by the
# "Next steps" summary, and absent from every receipt, so uninstall.sh — which removes only what the
# receipt lists — could never take it away. Permanent debris in exactly the projects that already had
# a CLAUDE.md of their own and where the installer politely declined to overwrite it.
#
# OUTSIDE THE BRANCH, for the reason the manifest-backup row is outside the flags. Exactly one of
# the block's arms writes this file, and a project leaves that arm for good the moment the user
# takes the block's own advice and adds the markers to their CLAUDE.md: every run from then on takes
# `refreshed`, the file run 1 wrote is still sitting on disk, and a row written where the file is
# created would vanish on run 2 and never come back.
#
# THERE IS NO REFERENCE COPY, so the ref argument is '' and owned_by_installer's first arm — compare
# against the toolkit's shipped copy — is skipped by construction. This file has no shipped copy: it
# is generated per project from that project's Unity version, packages and provider. What answers
# for it instead is the pair below, and both halves were measured on a fixture 2026-08-13:
#
#   `separate` — this run generated the file and moved it into place. The only thing that can speak
#                for install 1, where there is no previous receipt to consult (`arms=branch`).
#   the receipt — the only thing that can speak for a run that did not touch the file at all
#                (`arms=receipt` on a second install taking `refreshed`), and it is a checksum
#                comparison, so a CLAUDE.md.generated the user has since edited stops being ours and
#                is left alone (`arms=none`), exactly as an edited MCP-SETUP.md is.
#
# It fails closed on the case that matters: a CLAUDE.md.generated the user wrote satisfies neither
# half, gets no row, and uninstall.sh never touches it.
#
# Until 2026-08-13 that held only where the writing arm never ran — a project whose CLAUDE.md is
# absent or already carries the markers. Where it DID run, the `mv` had already replaced the user's
# file with our bytes before anything asked whose it was, and this row then correctly claimed a file
# that was byte-for-byte ours. The arm asks first now (see the disjunction above it), so the two
# halves below answer for a file that is still the one whose ownership is in question.
#
# The mode is read off the file rather than written down as 644: `mv` from mktemp carries 0600
# across, so this row records 600 where .mcp.json's records 644, and a hardcoded 644 here would be a
# receipt that disagrees with its own file. (Nothing reads the column today; that is not a reason to
# write something false into it.)
if [ "$CLAUDE_MD_BRANCH" = separate ] || owned_by_installer 'CLAUDE.md.generated' ''; then
  printf 'CLAUDE.md.generated\t%s\t%s\ttoolkit\n' \
    "$(sha_of "$PROJECT_DIR/CLAUDE.md.generated")" \
    "$(stat -c '%a' "$PROJECT_DIR/CLAUDE.md.generated" 2>/dev/null || echo 644)" >> "$RECEIPT_TMP"
fi

# ── Step 7: .gitignore ───────────────────────────────────────────────────────
#
# The DECISION is `gitignore_plan`'s, made once in Step 3b and already announced by the dry run.
# What is left here is acting on it. `add_ignore`'s per-entry `grep -qxF` moved INTO the plan rather
# than staying here, because it was stage 2 of the decision rather than a detail of the write —
# leaving it here would have left the announcement free to disagree with the file, which is the
# whole of the defect this replaces.
#
# NOT A BARE ASSIGNMENT, AND THE HAZARD IS THE ONE add_manifest_dependency'S CALL SITE ALREADY
# CARRIES SIX LINES ABOUT. Under `set -euo pipefail` a command substitution's exit status IS the
# assignment's, so a non-zero return from gitignore_plan would kill the installer at THIS line —
# which is AFTER the payload is written and BEFORE the receipt is. Measured on a scratch copy by
# injecting a `return 3`: exit 3, `ok Installed N file(s).`, `ok Generated CLAUDE.md`, and NO
# RECEIPT — the whole payload in a project uninstall.sh removes nothing from, because it removes
# only what a receipt lists. Every path through gitignore_plan returns 0 today; capturing the status
# makes that an invariant the installer SURVIVES the loss of rather than one it silently DEPENDS ON,
# and the `*)` arm below turns the loss into a warning and a skipped .gitignore instead of a dead run.
#
# GITIGNORE_CREATED IS THE ONLY THING THAT CAN ANSWER "IS THIS FILE OURS?" ON THE RUN THAT MAKES IT,
# and the row below is written on ownership rather than on that flag alone — see its own comment.
GITIGNORE_CREATED=0
GITIGNORE_PLAN_RC=0
GITIGNORE_PLAN="$(gitignore_plan)" || GITIGNORE_PLAN_RC=$?
[ "$GITIGNORE_PLAN_RC" -eq 0 ] || GITIGNORE_PLAN="failed with status $GITIGNORE_PLAN_RC"
case "${GITIGNORE_PLAN%%"$NL"*}" in
  covered)
    ok ".gitignore already covers .claude/ local state — left alone." ;;
  present)
    # NOTHING IS WRITTEN ON THIS BRANCH, INCLUDING THE TRAILING NEWLINE. The previous shape reached
    # the `printf '\n'` below before discovering it had nothing to append, so a .gitignore that held
    # all four entries and did not end in a newline got one byte appended under the banner
    # "already has our entries" — a write announced as a no-change.
    ok ".gitignore already has our entries." ;;
  append)
    # THE READ-ONLY REFUSAL, AND THIS SITE IS WHY THE CLASS IS WRITES RATHER THAN `mv`. Measured
    # 2026-08-17 on a project whose `.gitignore` is 0444 and lacks our entries: the bare
    # `printf … >> "$GITIGNORE"` below died with `Permission denied`, `set -e` ended the run at
    # **rc 1**, and everything after Step 7 — `.mcp.json`, `MCP-SETUP.md`, the whole Codex layer,
    # `Next steps:` — never ran, with the payload already on disk. A `.gitignore` a VCS is holding
    # read-only is the same trigger the two entry documents already handle; nothing about this file
    # makes an abort more appropriate, and the cost of the abort is larger.
    #
    # ONE APPEND, NOT FOUR-PLUS — AND THE OPEN'S STATUS AND THE WRITE'S ARE NOT THE SAME STATUS.
    # The old shape appended the separator, the header and each entry as separate redirections, so a
    # failure part-way through left a `.gitignore` carrying half our block — a state nobody chose, in
    # a file whose whole job is to be read line by line. Collapsing it into one redirection was
    # right; testing the GROUP was not. `{ …; } >> f` exits with the status of its LAST command, and
    # that command ended in `|| true`, so on a filesystem that accepts the open and refuses the write
    # the run printed `ok Updated .gitignore (4 entries)` over a `.gitignore` carrying part of our
    # block or none of it. Measured 2026-08-17 against `/dev/full` with the shipped shape byte for
    # byte: `printf: write error: No space left on device`, `grep: write error: …`, group status
    # **0**. Two controls, so the attribution is not a guess — dropping the `|| true` gave a non-zero
    # status on the same input, and making only the FIRST `printf` fail still gave 0. Before that
    # commit this state was a loud `set -e` death; the shape that fixed the abort made it a silent
    # lie, which is strictly worse and is the same trigger class (ENOSPC, I/O error) the commit
    # invoked to justify its sibling change to `.codex/hooks.json`.
    #
    # SO THE BLOCK IS BUILT FIRST AND WRITTEN BY ONE `printf`, whose status is the write's. No pipe,
    # so nothing to mask: the loop that counts the entries is the loop that assembles them, which is
    # also what removes the `grep -v '^$'` whose no-match return was the reason for the `|| true`.
    #
    # AND A FAILURE HERE IS STILL A PARTIAL FILE — a single `write(2)` can be short. What changed is
    # that the run now SAYS so instead of announcing a success; an append into the user's own file
    # cannot be made atomic the way the two entry documents' whole-file writes are, because appending
    # is not authorship and rewriting the file would claim it.
    #
    # THE COUNT IS THE PLAN'S, IN BOTH HALVES OF THE ARM. Until 2026-08-17 the refusal quoted
    # `$GITIGNORE_ENTRY_COUNT` — every entry we know about — while the dry run quoted the number
    # MISSING from the file. Measured on a read-only `.gitignore` already holding 2 of our 4: the dry
    # run said 3 and the run said 4, about one set, in a pair added under the rule that one predicate
    # asked in two places is one predicate only if both ask it at the same point. Both now count the
    # plan, which is the only number either half can act on.
    GITIGNORE_MISSING=0
    GITIGNORE_BLOCK=""
    while IFS= read -r e; do
      [ -n "$e" ] || continue
      GITIGNORE_MISSING=$((GITIGNORE_MISSING + 1))
      GITIGNORE_BLOCK="$GITIGNORE_BLOCK$e$NL"
    done <<< "${GITIGNORE_PLAN#*"$NL"}"
    if ! can_replace_or_report "$GITIGNORE" ".gitignore" "install.sh"; then
      note_not_done ".gitignore — the file is read-only, so this run appended none of its $GITIGNORE_MISSING missing entries and .claude/ local state (settings.local.json, the session file, uninstall backups) can still reach your commits. Make it writable and re-run install.sh."
      # $GITIGNORE_PLAN IS NOT REWRITTEN HERE, and the first draft of this arm rewrote it. The `case`
      # below reads the same variable to decide whether to add its own entry, and its `*)` arm says
      # *"its plan could not be computed"* — which is false of this state twice over: the plan was
      # computed correctly and this arm is acting on it. One outcome, one entry.
    else
      # THE CREATE'S OWN STATUS, AND `can_replace` CANNOT STAND IN FOR IT. That predicate is
      # `[ ! -e "$1" ] || [ -w "$1" ]`, so it returns 0 for an ABSENT path — correctly, since there is
      # no file there to be read-only — and `can_replace_or_report` waves this arm straight through
      # to a truncation that reads no status of its own. Measured 2026-08-17 on a project whose
      # `.gitignore` had been removed and whose root was then sealed: `install.sh: line 2456:
      # …/.gitignore: Permission denied`, `set -e`, **rc 1** mid-install, with `.mcp.json`,
      # `MCP-SETUP.md`, the entire Codex layer and `Next steps:` never running and the payload already
      # on disk. That is the same abort the read-only arm above was written to remove, one branch
      # over, in the member the class table called *"can_replace + status"* — the create is a
      # different question from the replace and needs its own answer.
      GITIGNORE_OPEN_OK=1
      if [ ! -f "$GITIGNORE" ]; then
        if : > "$GITIGNORE"; then
          GITIGNORE_CREATED=1
          info "Created .gitignore"
        else
          # NOTHING TO REMOVE ON THIS PATH. The truncation failed at the OPEN, so no file was
          # created; an `rm -f` here would be aimed at a path that does not exist, and on the state
          # that produces this failure it would be aimed at a directory that will not take the
          # unlink either.
          GITIGNORE_OPEN_OK=0
          warn ".gitignore does not exist and could not be created — the project root would not take it."
          note_not_done ".gitignore — it does not exist and could not be created, so none of its $GITIGNORE_MISSING entries were added and .claude/ local state (settings.local.json, the session file, uninstall backups) can still reach your commits. Check that the project root is writable and re-run install.sh."
        fi
      fi
      if [ "$GITIGNORE_OPEN_OK" -eq 1 ]; then
        GITIGNORE_SEP=""
        # Only append a newline first if the file does not already end with one; otherwise our header
        # lands on the end of their last line.
        if [ -s "$GITIGNORE" ] && [ -n "$(tail -c1 "$GITIGNORE")" ]; then GITIGNORE_SEP=$'\n'; fi
        if printf '%s\n# Claude Code local settings and session state\n%s' \
             "$GITIGNORE_SEP" "$GITIGNORE_BLOCK" >> "$GITIGNORE"; then
          ok "Updated .gitignore ($GITIGNORE_MISSING entries)"
        else
          warn ".gitignore could not be appended to — the write failed, so it carries some of our"
          warn "block or none of it rather than all of it."
          note_not_done ".gitignore — the append failed part-way or at the first byte, so some or none of its $GITIGNORE_MISSING entries are in the file and .claude/ local state can still reach your commits. Check the entries under '# Claude Code local settings and session state' by hand, then re-run install.sh."
        fi
      fi
    fi ;;
  *)
    # The dry run's `*)` arm announces this same outcome as a decline, so the two readers still
    # agree on the branch neither of them can reach today.
    warn "gitignore_plan gave an unusable verdict (${GITIGNORE_PLAN%%"$NL"*}) — .gitignore left alone, and the install continues." ;;
esac
# THE CONSEQUENCE, NAMED. The warn above says what the installer did (nothing) and not what that
# costs, and the cost is specific: these are the paths that leak local state into someone's commits.
# The entries are listed from $GITIGNORE_ENTRIES rather than written out, so this line cannot drift
# from the set Step 7 would have appended — the drift this whole plan/act split exists to prevent.
#
# INSIDE AN `if`, NOT AS A FIFTH `case` ARM: the `*)` arm above is the fallback, and a second `*)`
# is not a thing. Reading $GITIGNORE_PLAN once more here is reading the same variable the case just
# read, not recomputing the plan.
case "${GITIGNORE_PLAN%%"$NL"*}" in
  covered|present|append) ;;
  *)
    # awk drains its input to the end, so this pipeline cannot SIGPIPE the writer.
    note_not_done ".gitignore — its plan could not be computed, so nothing was written to it and these are NOT ignored: $(printf '%s\n' "$GITIGNORE_ENTRIES" | awk 'NF { if (n++) printf ", "; printf "%s", $0 } END { printf "\n" }'). Add them by hand, or your local settings and session state land in your commits."
    ;;
esac

# A .gitignore THIS INSTALLER CREATED is a file we own. One the user already had is not, whatever we
# appended to it — appending is not authorship, and claiming their file would let uninstall.sh delete
# it. That asymmetry is the whole of the decision, and `GITIGNORE_CREATED` is the only thing that can
# see it: after the write, a created file and an appended-to one are both just a .gitignore with our
# four entries in it, and nothing on disk tells them apart.
#
# Without a row the created file was permanent debris. It is the fourth member of a family this file
# has now closed three times — Packages/manifest.json.bak, CLAUDE.md.generated, MCP-SETUP.md — and
# the one the `find`-snapshot oracle of the previous wave structurally could not see, because on
# every fixture but `bare` the path already exists before the run and a path snapshot shows no new
# file.
#
# OWNERSHIP, NOT AUTHORSHIP, so the disjunction rather than the flag alone. Run 1 creates the file;
# run 2's plan is `present` (all four entries are already lines) and appends nothing, so a row
# written only where the file is created would vanish on run 2 and the debris would come straight
# back one run later. That is state B's defect, and states M and M3 hold both halves.
#
# THERE IS NO REFERENCE COPY — the file is the user's project's, not a payload file — so the ref
# argument is '' and owned_by_installer's first arm is skipped by construction. What answers is the
# previous receipt, and it is a checksum comparison: the moment the user adds a line of their own,
# the file stops being ours and is left alone (state M3). The cost of that is our four entries
# staying in a file we no longer claim, which is the same trade an edited MCP-SETUP.md already makes.
#
# The mode is read off the file rather than written as 644: `: > "$GITIGNORE"` creates under the
# caller's umask, and a hardcoded value here would be a receipt that disagrees with its own file.
if [ -f "$GITIGNORE" ] \
   && { [ "$GITIGNORE_CREATED" -eq 1 ] || owned_by_installer '.gitignore' ''; }; then
  printf '.gitignore\t%s\t%s\ttoolkit\n' \
    "$(sha_of "$GITIGNORE")" \
    "$(stat -c '%a' "$GITIGNORE" 2>/dev/null || echo 644)" >> "$RECEIPT_TMP"
fi

# ── Step 8: Optional — manifest.json package additions ───────────────────────
# One helper for every "--with-X adds a package to Packages/manifest.json" flag, so --with-mcp and
# --with-input-system share the same surgical insert, the same backup behaviour, and the same
# "could not edit safely" fallback rather than two hand-maintained copies drifting apart.
#
# $MANIFEST_BAK_REL is defined in Step 3b, not here: the dry-run block announces this file and had
# to be able to name it. One definition, derived from $MANIFEST, so the receipt row, the
# announcement and the file they both name cannot disagree.
MANIFEST_BAK_KEPT=0
# MANIFEST_DECLINED USED TO BE DECLARED HERE, one flag per line, read by a `Not done:` block at the
# bottom of the file that knew about this function and nothing else. It is now `$NOT_DONE` at the top
# — same idiom, same "set where the decision is made, read where the run speaks to the user", every
# other abandonment site as well. All three abandonment outcomes in this function record through it, and the fourth
# outcome (the package is already there) is not an abandonment: the manifest ends the run in the
# state the flag asked for.
add_manifest_dependency() {
  local pkg_name="$1" pkg_value="$2" flag_name="$3"
  if [ ! -f "$MANIFEST" ]; then
    warn "No Packages/manifest.json — skipping $flag_name."
    note_not_done "$flag_name — skipped: this project has no Packages/manifest.json, so $pkg_name was not added. Open the project in Unity once to create the manifest, then re-run with $flag_name."
    return
  fi
  if grep -q "$pkg_name" "$MANIFEST"; then
    ok "$pkg_name already in manifest.json."
    return
  fi
  # ASK BEFORE WRITING, and decline THE EDIT — not just the backup. The `cp` below used to be
  # unconditional: --with-mcp on a project missing both packages keeps a backup, the user edits it,
  # and --with-input-system in a later run overwrote it while the same run printed
  # `keeping yours: Packages/manifest.json.bak`.
  #
  # THE ASYMMETRY WITH CLAUDE.md.generated IS DELIBERATE. There the installer keeps the user's file
  # and proceeds; here it abandons the flag. A backup exists to make a risky edit recoverable, so
  # making the edit while skipping the backup keeps the risk and drops the mitigation — and this
  # project is by definition not under git, which is the only reason the backup is kept at all, so
  # there is no second copy to fall back on. Writing the backup under another name was rejected: it
  # trades one destroyed file for unbounded debris, and each such file needs a receipt row of its own.
  #
  # THREE DISJUNCTS, and the middle one is this run's own knowledge. `owned_by_installer` consults
  # the PREVIOUS receipt, which cannot know about a backup THIS run just made — so on a single
  # `--with-mcp --with-input-system` run against a project missing both packages, the second caller
  # would find the first caller's backup, fail to recognise it, and decline. That is state J's shape,
  # and MANIFEST_BAK_KEPT is what the row below already uses to answer it.
  #
  # RETURNS ZERO, AND RECORDS THE DECLINE FOR THE SUMMARY. Two separate decisions; the second exists
  # because the first, alone, let a run end green about work it did not do.
  #
  # The status: the callers are `[ "$WITH_MCP" -eq 1 ] && add_manifest_dependency ...` — AND-lists in
  # which the function is the command after the final `&&`, so `set -e` DOES apply to it. Measured on
  # a scratch copy 2026-08-13: a `return 1` here exits the installer at the call site with status 1,
  # before Step 8b, Step 8c and Step 9 — so the project keeps the whole payload and NO RECEIPT, and
  # uninstall.sh, which removes only receipt-listed paths, can then never clean any of it up. That is
  # a worse failure than the one this guard closes.
  #
  # This path is also a member of an existing family. Three other outcomes already mean "the flag did
  # not happen": no manifest, package already present, and `Could not edit manifest.json safely` —
  # which prints the same "add this under \"dependencies\" yourself" block this one does. All three
  # return zero and let the run exit zero, because install.sh's status answers "did the installation
  # happen", and it did: the payload is written, the receipt is written, uninstall.sh works. Making
  # one of four such outcomes non-zero would leave the status meaning different things on different
  # flag failures, which is a new inconsistency in place of the one being fixed.
  #
  # What the status genuinely cannot carry, the summary must. `note_not_done` appends to the global
  # $NOT_DONE — this function is called once per flag, so two flags can record two lines — and that
  # drives the `Not done:` block beside the green banner: set where the decision is made, read where
  # the run speaks to the user. Without it the only trace of an abandoned flag was four warn lines a
  # dozen lines above `Installation complete.` and an exit status of 0. The mechanism was
  # MANIFEST_DECLINED, private to this function; it is now the shared one every site uses, and
  # the exit contract in MCP-SETUP.md is what says out loud that the block is complete.
  if [ -e "$MANIFEST.bak" ] && [ "$MANIFEST_BAK_KEPT" -ne 1 ] && ! owned_by_installer "$MANIFEST_BAK_REL" ''; then
    warn "$MANIFEST_BAK_REL exists and is not ours — declining $flag_name rather than overwriting it."
    warn "That file is the backup this edit needs to stay undoable. Move it aside and re-run with"
    warn "$flag_name, or add this under \"dependencies\" yourself:"
    warn "    \"$pkg_name\": \"$pkg_value\""
    note_not_done "$flag_name — declined: $MANIFEST_BAK_REL is not ours to overwrite, so the manifest was not edited. Move that file aside and re-run with $flag_name, or add \"$pkg_name\": \"$pkg_value\" under \"dependencies\" by hand."
    return 0
  fi
  # Surgical insert. The old installer round-tripped the JSON through a re-indenting dump, which
  # reformatted the user's whole manifest to add one line.
  #
  # THE BACKUP'S OWN STATUS. This `cp` is the first write of the edit and the one the rollback below
  # depends on; as a bare command a failure ended the run before either. Declining the flag is the
  # posture this function already takes when the backup is not ours to overwrite — same outcome, same
  # shape of message, one line of remedy.
  if ! cp "$MANIFEST" "$MANIFEST.bak"; then
    warn "Could not write $MANIFEST_BAK_REL — declining $flag_name rather than editing the manifest"
    warn "with no way back. Add this under \"dependencies\" yourself:"
    warn "    \"$pkg_name\": \"$pkg_value\""
    note_not_done "$flag_name — the pre-edit backup could not be written, so the manifest was left alone and $pkg_name was not added. Add \"$pkg_name\": \"$pkg_value\" under \"dependencies\" in Packages/manifest.json yourself."
    return 0
  fi
  if sed -i.tmp "s|\"dependencies\"[[:space:]]*:[[:space:]]*{|\"dependencies\": {\n    \"$pkg_name\": \"$pkg_value\",|" "$MANIFEST" 2>/dev/null && grep -q "$pkg_name" "$MANIFEST"; then
    rm -f "$MANIFEST.tmp"
    # If git already tracks the manifest, git IS the backup — keeping a .bak just drops untracked
    # debris into someone's repo for no benefit.
    if git -C "$PROJECT_DIR" ls-files --error-unmatch Packages/manifest.json >/dev/null 2>&1; then
      rm -f "$MANIFEST.bak"
      ok "Added $pkg_name to manifest.json"
      # Naming only manifest.json here would be half the truth: the next time Unity opens the
      # project it resolves the package and writes packages-lock.json too, which is also tracked.
      # Reverting one and not the other leaves the lock referencing a package the manifest no
      # longer asks for.
      if git -C "$PROJECT_DIR" ls-files --error-unmatch Packages/packages-lock.json >/dev/null 2>&1; then
        info "To undo: git checkout Packages/manifest.json Packages/packages-lock.json"
        info "  (Unity writes the lock file when it next resolves packages.)"
      else
        info "To undo: git checkout Packages/manifest.json"
      fi
    else
      # KEPT, so ours. Recorded once, after both callers have run, rather than here: --with-mcp and
      # --with-input-system can both reach this line in one run, and the second `cp` above has
      # already overwritten the first's backup. Two rows for one path would then disagree on the
      # checksum, and uninstall.sh would report the stale one under "you modified" while removing
      # the file under the fresh one.
      MANIFEST_BAK_KEPT=1
      ok "Added $pkg_name to manifest.json (backup: manifest.json.bak)"
    fi
  else
    # THE ROLLBACK'S OWN STATUS, READ SINCE 2026-08-17, AND THE MANIFEST IS UNCHANGED ON EVERY INPUT
    # THAT REACHES HERE. Trace the two ways in: `sed -i` failed, so it wrote nothing; or `sed`
    # succeeded and `grep -q` did not find the package, which means the substitution matched nothing
    # and `sed` rewrote the file with identical bytes. Either way the manifest a user opens Unity with
    # is byte-for-byte the one this run found — measured, sha unchanged.
    #
    # SO WHAT THE ROLLBACK ACTUALLY RESTORES IS NOTHING, AND WHAT ITS FAILURE LEAVES IS A FILE, NOT A
    # STATE. This block said the opposite for one commit: *"Packages/manifest.json is NOT as this run
    # found it … restore it by hand before opening the project in Unity"*, and it suppressed the
    # sibling entry's *"so it is unchanged"* as if that were the false one. It was the true one. The
    # entry below is one sentence for one outcome, with the debris named as debris.
    #
    # AND THE CLAIM THAT NO FIXTURE COULD REACH THIS WAS FALSE. It read *"the second needs `Packages/`
    # unwritable, which kills the `cp` four lines up … a race, not a fixture."* Overwriting an
    # EXISTING file needs write permission on the file, not on the directory — and after any
    # `--with-mcp` install on a project git does not track, `Packages/manifest.json.bak` already
    # exists and is ours. `Packages/` at 555 then reaches this arm deterministically, first try, with
    # no race: `cp` succeeds onto the existing backup, `sed -i` fails because it needs directory write
    # for its temp, and the `mv` fails. `tests/test-install-not-done.sh` builds exactly that.
    MANIFEST_ROLLED_BACK=1
    if ! mv "$MANIFEST.bak" "$MANIFEST"; then
      MANIFEST_ROLLED_BACK=0
      warn "$MANIFEST_BAK_REL could not be moved back over the manifest — but the failed edit did not"
      warn "change Packages/manifest.json either, so it is as this run found it and that file is a copy."
      # RECORDED AS OURS, so the debris has a way out. Without this the flag stays 0, the row below is
      # never written, and a backup this run created is permanent debris that `uninstall.sh` — which
      # removes only receipt-listed paths — can never take away. That is the defect the row exists to
      # close, arriving through the failure path instead of the success one.
      MANIFEST_BAK_KEPT=1
      note_not_done "$flag_name — the manifest could not be edited safely, so Packages/manifest.json is unchanged and $pkg_name was not added. The pre-edit backup could not be removed either, so $MANIFEST_BAK_REL is left beside it holding the same content; it is recorded as ours, so uninstall.sh will take it. Add \"$pkg_name\": \"$pkg_value\" under \"dependencies\" yourself."
    fi
    rm -f "$MANIFEST.tmp"
    # THE FLAG MUST NOT OUTLIVE THE FILE IT NAMES. The `mv` above has just consumed the backup, and
    # this function is called once per --with-* flag: on a two-flag run where the first caller
    # succeeded and kept its backup, MANIFEST_BAK_KEPT is already 1 when the second caller reaches
    # this arm and deletes the file. The row below then fires on a path that is gone, and because
    # `sha_of` sits inside a `printf` ARGUMENT — where `set -e` does not reach — the miss does not
    # kill the run: it writes a row with an EMPTY checksum, which uninstall.sh silently declines to
    # act on. A row that removes nothing is indistinguishable on disk from no row at all, and worse
    # than one, because it reads as coverage.
    #
    # ONLY WHEN THE ROLLBACK CONSUMED IT. If the rename failed, the backup is still on disk and the
    # arm above has just claimed it so `uninstall.sh` can take it away; clearing the flag here would
    # throw that claim away one line later and put the debris back out of reach.
    if [ "$MANIFEST_ROLLED_BACK" -eq 1 ]; then MANIFEST_BAK_KEPT=0; fi
    warn "Could not edit manifest.json safely — add this under \"dependencies\" yourself:"
    warn "    \"$pkg_name\": \"$pkg_value\""
    # THE THIRD MEMBER OF THE FAMILY THE COMMENT ABOVE ENUMERATES, and until now the only one of the
    # four with no trace in the summary at all. The surgical `sed` matches nothing in a manifest with
    # no "dependencies" key — a real shape, and the one the plan reproduced — and the failure arm
    # restores the original, so the run ends with the manifest byte-identical and the flag silently
    # gone. `$MANIFEST_BAK_REL` is not offered as a remedy here: the `mv` above has just consumed it.
    #
    # CONDITIONAL, BECAUSE THE FAILED-ROLLBACK PATH PRINTS ITS OWN — one outcome, one entry, and the
    # two say the same thing about the manifest. *"So it is unchanged"* is true on BOTH paths: this
    # arm is reached only when the edit wrote nothing or wrote identical bytes. A version of this
    # comment claimed the clause was the rollback's to make and suppressed it there; the sentence it
    # promoted in its place — *"is NOT as this run found it"* — was false on every reachable input.
    if [ "$MANIFEST_ROLLED_BACK" -eq 1 ]; then
      note_not_done "$flag_name — the manifest could not be edited safely, so it is unchanged and $pkg_name was not added. Add \"$pkg_name\": \"$pkg_value\" under \"dependencies\" in Packages/manifest.json yourself."
    fi
  fi
}

[ "$WITH_MCP" -eq 1 ] && add_manifest_dependency "$MCP_PKG_NAME" "$MCP_PKG_URL" "--with-mcp"
[ "$WITH_INPUT_SYSTEM" -eq 1 ] && add_manifest_dependency "$INPUT_SYSTEM_PKG_NAME" "$INPUT_SYSTEM_PKG_VERSION" "--with-input-system"

# A backup we keep is a file we own. Without this row uninstall.sh — which removes only what the
# receipt lists — could never take it away, so manifest.json.bak was permanent debris in exactly the
# projects least able to `git checkout` it back: the ones not under git, which is the only condition
# under which it is kept at all.
#
# OUTSIDE THE FLAGS, NOT JUST OUTSIDE THE BRANCHES, and for the reason owned_by_installer exists.
# `add_manifest_dependency` returns early once the package is already in the manifest, and a run
# passing no --with-* flag never calls it — so on every install after the first, the branch that
# makes the backup does not execute while the backup sits on disk untouched. A row written where the
# file is created vanishes on run 2 and the debris comes straight back. Measured on a fixture:
# --with-mcp, then a plain install, and the .bak is still there.
#
# Two disjuncts, and neither is redundant. The first is knowledge: this run made the copy and chose
# to keep it. The second is the previous receipt, which is the only thing that can answer for a file
# no branch in this run touched — and it is a checksum comparison, so a backup the user has since
# edited stops being ours and is left alone, exactly as an edited MCP-SETUP.md is.
#
# It fails closed on the case that matters: a Packages/manifest.json.bak the user wrote themselves
# satisfies neither disjunct, gets no row, and uninstall.sh never touches it. Until 2026-08-13 the
# `cp` above could still overwrite such a file before anything asked whose it was, at which point
# this row correctly claimed bytes that were ours; the helper asks first now and declines the flag
# outright, so the disjuncts below answer for the file whose ownership is actually in question.
#
# THE `-f` IS THE BELT TO THAT BRACES. `owned_by_installer` already opens with an existence test, so
# it guards only the first disjunct — this run's own knowledge, which the failure arm above can
# invalidate between the flag being set and this line being reached. Two independent conditions have
# to be wrong before an empty-checksum row can be written now, and the two are in different
# functions.
if [ -f "$PROJECT_DIR/$MANIFEST_BAK_REL" ] \
   && { [ "$MANIFEST_BAK_KEPT" -eq 1 ] || owned_by_installer "$MANIFEST_BAK_REL" ''; }; then
  printf '%s\t%s\t%s\ttoolkit\n' \
    "$MANIFEST_BAK_REL" \
    "$(sha_of "$PROJECT_DIR/$MANIFEST_BAK_REL")" \
    "$(stat -c '%a' "$PROJECT_DIR/$MANIFEST_BAK_REL" 2>/dev/null || echo 644)" >> "$RECEIPT_TMP"
fi

# ── Step 8b: .mcp.json — the file Claude Code actually reads MCP servers from ──
# Project-scoped MCP servers live in .mcp.json at the project root, not in .claude/settings.json.
# Claude Code silently ignores an mcpServers key there, so writing it was the whole defect: the
# unity-* agents had no tools to call. See MCP-SETUP.md for the approval step this still requires.
MCP_JSON="$PROJECT_DIR/.mcp.json"
cat > "$MCP_JSON_REF" <<'MCPJSON'
{
  "mcpServers": {
    "UnityMCP": {
      "type": "http",
      "url": "http://localhost:8080/mcp"
    }
  }
}
MCPJSON
if [ ! -f "$MCP_JSON" ]; then
  # `cat > ` rather than `cp`, so the file is created under the caller's umask the way the heredoc
  # that used to sit here did. `cp` would carry mktemp's 0600 across and contradict the 644 the
  # receipt row records.
  #
  # THE STATUS IS READ, for the reason the write class's table gives: this creation fails on a
  # project root the user has sealed, and as a bare command it took the whole run down at rc 1 with
  # the payload already on disk. There is no `can_replace` test because this arm runs only when the
  # path does not exist — there is no user file here to be read-only, only a directory that will not
  # take a new entry.
  if cat "$MCP_JSON_REF" > "$MCP_JSON"; then
    ok "Wrote .mcp.json (UnityMCP → http://localhost:8080/mcp)"
  else
    rm -f "$MCP_JSON"
    warn ".mcp.json could not be written — the project root would not take it."
    note_not_done ".mcp.json — it could not be written, so the unity-* agents have no MCP server entry to reach. Check that the project root is writable and re-run install.sh."
  fi
elif grep -Eq '"(unityMCP|UnityMCP)"' "$MCP_JSON" 2>/dev/null; then
  ok ".mcp.json already has a unityMCP/UnityMCP entry — left alone."
else
  warn ".mcp.json exists without a UnityMCP entry — not rewriting it. Add this under \"mcpServers\":"
  warn ''
  warn '    "UnityMCP": {'
  warn '      "type": "http",'
  warn '      "url": "http://localhost:8080/mcp"'
  warn '    }'
  # NOT A `keeping yours` KEEP. Nothing of ours is on disk at that path to keep — the file is
  # entirely the user's, and what is missing is the server entry every unity-* agent's
  # mcp__UnityMCP__* tools resolve through. Without it those agents load with tools that cannot be
  # called, which is silent at install time and looks like a broken bridge later.
  note_not_done ".mcp.json — yours has no UnityMCP entry and was not rewritten, so the unity-* agents have no MCP server to reach. Add the \"UnityMCP\" block printed above under \"mcpServers\"."
fi
# Outside the branches on purpose — see owned_by_installer. The "already has a UnityMCP entry" arm
# above is exactly where the two cases are indistinguishable by inspection: our own file from the
# previous run, and a user's file that happens to name the same server. Only the checksum tells
# them apart, so only the checksum decides.
if owned_by_installer '.mcp.json' "$MCP_JSON_REF"; then
  printf '.mcp.json\t%s\t644\ttoolkit\n' "$(sha_of "$MCP_JSON")" >> "$RECEIPT_TMP"
fi

# ── Step 8c: MCP-SETUP.md — the setup guide the "Next steps" summary points at ──
# It used to point a freshly installed project at MCP-SETUP.md while never installing it: the
# payload is .claude/** only, so the file was absent from every project this toolkit set up. Copied
# alongside CLAUDE.md (project root, never overwritten if the user already has one) so the pointer
# in the summary below actually resolves.
MCP_SETUP_MD="$PROJECT_DIR/MCP-SETUP.md"
if [ -f "$SCRIPT_DIR/MCP-SETUP.md" ] && [ ! -f "$MCP_SETUP_MD" ]; then
  # Status read, same member of the same class as .mcp.json above: a copy into a sealed project root
  # is a failure this run has to report rather than die on, and the summary a few hundred lines below
  # points at this file by name whether or not it landed.
  if cp "$SCRIPT_DIR/MCP-SETUP.md" "$MCP_SETUP_MD"; then
    ok "Installed MCP-SETUP.md"
  else
    rm -f "$MCP_SETUP_MD"
    warn "MCP-SETUP.md could not be written — the project root would not take it."
    note_not_done "MCP-SETUP.md — it could not be written, so the bridge-setup guide the 'Next steps' summary points at is not in this project. Check that the project root is writable and re-run install.sh."
  fi
# THE ONLY KEEP IN THIS FILE THAT SAID NOTHING AT ALL. Every other one reports: `keeping yours` lists
# the payload files, the CLAUDE.md.generated arm warns twice, .mcp.json prints the block it did not
# write. This branch printed no line in the entire run, while the "Next steps" summary below went on
# pointing at MCP-SETUP.md — which now resolves to the user's file, and which is where this
# installer's exit contract is written down.
#
# A REPORT, NOT A `Not done:` ENTRY, and the boundary is the one $NOT_DONE's header states. The file
# at that path is the user's own — either they wrote it or they edited ours — and keeping it is the
# ownership rule working, not work abandoned. It belongs in the same class as `keeping yours`, which
# is reported and counted and stays out of the block.
#
# `owned_by_installer` is CALLED rather than restated; it is the same predicate, with the same
# reference copy, that the row below decides ownership with. On the ordinary re-install it answers
# yes and this branch is silent, which is the point: the warning fires where the toolkit's guide is
# genuinely not the file on disk.
elif [ -f "$SCRIPT_DIR/MCP-SETUP.md" ] && ! owned_by_installer 'MCP-SETUP.md' "$SCRIPT_DIR/MCP-SETUP.md"; then
  warn "MCP-SETUP.md at the project root is not ours — keeping yours, untouched."
  warn "This version's bridge-setup guide was not installed, and the 'Next steps' pointer below"
  warn "resolves to your file. Compare it against $SCRIPT_DIR/MCP-SETUP.md if the bridge misbehaves."
fi
# Same shape as .mcp.json's row above, and for the same reason: the row states what we own at the
# end of the run, not what this run happened to write.
if owned_by_installer 'MCP-SETUP.md' "$SCRIPT_DIR/MCP-SETUP.md"; then
  printf 'MCP-SETUP.md\t%s\t644\ttoolkit\n' "$(sha_of "$MCP_SETUP_MD")" >> "$RECEIPT_TMP"
fi

# ── Step 8d: the Codex CLI layer ─────────────────────────────────────────────
#
# WHY IT IS HERE AND NOT ANYWHERE EARLIER, AND THIS IS A CONTRACT RATHER THAN A PREFERENCE.
#
# `--emit-config` writes the shim's ABSOLUTE path into all twelve command strings, choosing it by
# preferring `<project>/.claude/scripts/codex-hook-shim.sh` and falling back to the toolkit clone it
# was invoked from. The scripts loop that puts the shim in the project is Step 5. Emit before it and
# every entry points into this checkout — a directory the user is under no obligation to keep — and
# per findings.md `## Hooks` a hook command Codex cannot run is a silent ALLOW, not an error. The
# result is nine registered hooks enforcing nothing: the exact defect the shim exists to close,
# reintroduced by sequence alone.
#
# NOTHING IN THE SUITE COULD CATCH THAT FROM THE OUTSIDE. tests/test-codex-surface.sh's section 4
# installs and THEN emits, so it exercises the generator's preference logic, not an installer's
# order. Section 9 of that file now makes the assertion that can only be made from here — on a FRESH
# install, the one shape where the ordering is observable, because on a re-install the project's own
# copy is already there from run 1 and the wrong order picks it up anyway. Two defences, because one
# of them is a test that can be deleted: the block below REFUSES TO EMIT unless the shim is already
# in the project, and refuses to INSTALL a config any of whose paths cannot run.
#
# THE CLAUDE CODE ARM DOES NOT ENTER THIS BLOCK AT ALL. Everything below is inside one `if`, so a
# default invocation executes not one line of it — except CODEX_TRUST_REL, which is declared beside
# RECEIPT_REL at the top of this file because THREE readers outside this block need it: Step 8e's
# carry-forward, the dry run's Codex-layer announcement, and this block. It lived here until
# 2026-08-16, and moving the announcement above it produced `CODEX_TRUST_REL: unbound variable` and
# rc 1 on every `--dry-run` against a project with an existing receipt — a `set -u` death in the one
# command whose entire job is to write nothing and tell you what would happen.

# Every path a Codex hook command names, checked for the two ways it can be unrunnable. Printed one
# defect per line; empty output means the config is safe to install.
#
# `grep -o` over the file rather than jq: the paths are single-quoted inside the command strings —
# that quoting is the generator's own, and it is what Codex's shell sees — so the quotes are the
# delimiter to read. It also keeps the Claude Code arm free of a jq dependency it never had.
codex_config_defects() {   # $1 = config file
  local f="$1" p seen=0
  [ -f "$f" ] || { printf 'not a file: %s\n' "$f"; return 0; }
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    seen=$((seen + 1))
    if [ ! -f "$p" ]; then printf 'names a file that does not exist: %s\n' "$p"; continue; fi
    case "$p" in
      "$PROJECT_DIR"/*) ;;
      *) printf 'names a path outside the project: %s\n' "$p" ;;
    esac
  done <<< "$(grep -o "'[^']*'" "$f" 2>/dev/null | tr -d "'" | sort -u || true)"
  # A config with no command path at all registers nothing and reads as healthy. Named rather than
  # passed: the whole failure class here is "looks installed, enforces nothing".
  [ "$seen" -gt 0 ] || printf 'carries no command path at all\n'
}

if [ "$CLIENT" = codex ]; then
  info "Codex CLI layer (second client)"
  CODEX_DIR="$PROJECT_DIR/.codex"
  CODEX_SKILL_ROOT="$PROJECT_DIR/.agents/skills"
  CODEX_HOOKS_JSON="$CODEX_DIR/hooks.json"
  CODEX_CFG="$CODEX_DIR/config.toml"

  # ── 8d.1 AGENTS.md, the entry document ──────────────────────────────────
  # Codex INJECTS this file whole, before the turn — measured, sentinel returned with 0 shell
  # commands — where CLAUDE.md is merely findable. That is what makes overwriting a user's own
  # AGENTS.md the most expensive mistake available on this arm, and why the decline comes first.
  #
  # IT GETS THE MARKED-REGION MERGE NOW, AND THAT REVERSES A DECISION TASK 9 ARGUED DELIBERATELY.
  # This block read: *"No marker-pair merge, unlike CLAUDE.md. The generated Codex document has no
  # `separate` sibling and no in-place refresh arm, because there is no established convention of
  # hand-written prose in an AGENTS.md this installer wrote."* That was sound while the file carried
  # only generated content. **The premise changed and the conclusion followed it:**
  #
  #   * The installer's own Codex Next step 2 tells the user to fill in this file's FILL: markers. So
  #     hand-written prose in an AGENTS.md this installer wrote is not merely a convention, it is an
  #     INSTRUCTION — and the moment the user followed it the file was frozen for good. Measured
  #     2026-08-17 on a urp fixture, install → fill the nine markers → install twice more: run 2 said
  #     `keeping yours, untouched` and dropped the row; run 3 could no longer even list it under local
  #     edits, because the loop that produces that list reads the receipt; `studio-doctor.sh` reported
  #     `98 file(s) verified` and never named it; `uninstall.sh` removed 98 and left it behind
  #     unreported. A frozen skill stays a file this toolkit knows about — a frozen AGENTS.md stopped
  #     being one.
  #   * Task 12 then made a correctness rule depend on this file: the `/name` translation reaches a
  #     Codex session because the always-injected AGENTS.md carries it. A frozen copy of a rule is a
  #     rule that stops being true.
  #
  # WHAT THE MERGE REACHES, AND IT IS LESS THAN THE SECOND BULLET NEEDS — SAID HERE RATHER THAN LEFT
  # FOR SOMEONE TO DISCOVER. `emit_marked_region` in the generator emits exactly `## Project Facts`,
  # the detected-stack verdict and the provider verdict. Everything else in this document — the
  # `FILL:` vision half, `## Running under Codex CLI` with the `/name` translation bullet, the
  # hooks-and-trust paragraph, the sub-agents paragraph, `## Non-negotiables not covered by a gate` —
  # is emitted OUTSIDE the pair, by the full generate only. Measured 2026-08-17 with a sentinel line
  # patched in above the `/name` bullet: it lands on a fresh install and does NOT land on an upgrade
  # over a filled-in AGENTS.md. So this merge un-freezes the project facts and nothing else; every
  # Codex-specific rule in the document stays as install 1 wrote it, permanently, once the user makes
  # the edit step 2 asks for.
  #
  # THAT IS A DELIBERATE BOUNDARY AND NOT AN OVERSIGHT. Widening the region to cover those sections
  # would convert bytes the user may already have edited into bytes this installer replaces wholesale
  # on every run — on existing projects, retroactively — which is the class of loss this whole task
  # exists to prevent, and the marker contract is shared with CLAUDE.md and stated to the model in
  # `.claude/commands/unity-init.md`, so moving it is a change to three surfaces rather than a fix
  # here. The consequence is carried instead: the `/name` rule keeps its second home in
  # `.claude/skills/using-kinglet/SKILL.md`, and CLAUDE.md's Codex-qualification criterion says so
  # with this measurement rather than with the freeze it used to cite.
  #
  # WHAT DID NOT COME BACK WITH IT, AND THIS HALF OF TASK 9'S ARGUMENT STILL STANDS. There is no
  # `AGENTS.md.generated` sibling. CLAUDE.md has one because a project that already has a CLAUDE.md is
  # the common case and the toolkit still owes that user the block; an AGENTS.md with no markers is
  # somebody else's entry document (Codex's own, or another tool's), and a second file beside it would
  # be a path Codex never injects, that nothing reads, that uninstall must then own — debris with a
  # receipt row. The `none` state is kept exactly as Task 9 left it: yours is kept, untouched, and
  # said out loud.
  #
  # SO THE BRANCHES ARE: ours -> rewritten whole; absent -> generated; edited-but-ours-once ->
  # the region refreshed and the prose kept; not ours and marker-less -> kept; markers that are not
  # one ordered pair -> declined WITH the diagnosis, exactly as CLAUDE.md declines. The predicate,
  # the diagnosis, the remedy and the merge are the same four functions CLAUDE.md's arm calls.
  AGENTS_MD="$PROJECT_DIR/AGENTS.md"
  AGENTS_BRANCH=skipped
  # `absent` for a path that is a directory or a dangling link too — `marked_region_state` opens with
  # `[ -f ]`. That is why the ownership arms below test `-e` as well: `mv` onto a directory moves the
  # file INSIDE it rather than replacing it, which is the trap CLAUDE.md's beside-yours arm records.
  AGENTS_MARKER_STATE="$(marked_region_state "$AGENTS_MD")"
  # A previous run wrote this file, whatever has happened to it since. It is what separates "ours,
  # which the user then filled in" — the refresh case, and the one the installer told them to create
  # — from "a file of the user's we have never written", which is kept and never claimed.
  #
  # IT TRUSTS THE RECEIPT, AND A HAND-EDITED RECEIPT IS THEREFORE WRITE PERMISSION. Append a
  # `user-modified` row for AGENTS.md by hand and the next run merges into whatever marked file sits
  # there. That is not a new class and it is not narrowable from here: a hand-edited `toolkit` row
  # already authorises a FULL overwrite through `owned_by_installer` one line down, and every reader
  # of this receipt trusts it by construction — `uninstall.sh` deletes on it. What is new is only that
  # `user-modified` rows, which granted no write anywhere before, now grant this one. Recorded rather
  # than guarded, on the same ground the file takes elsewhere: the receipt is inside the trust
  # boundary, and a predicate that second-guessed it would need a second source of truth this
  # installer does not have.
  AGENTS_WAS_OURS=0
  if receipt_has 'AGENTS.md'; then AGENTS_WAS_OURS=1; fi
  if [ ! -f "$GEN" ]; then
    warn "$GEN not found — AGENTS.md was not generated."
    note_not_done "AGENTS.md — the generator is missing, so this project has no Codex entry document. Codex injects that file whole, so without it none of the toolkit's conventions reach a Codex session."
  elif [ -e "$AGENTS_MD" ] && ! owned_by_installer 'AGENTS.md' '' \
       && [ "$AGENTS_MARKER_STATE" = wellformed ] && [ "$AGENTS_WAS_OURS" -eq 1 ]; then
    # THE REFRESH. Same contract CLAUDE.md's has: the generator owns every byte between the markers
    # and nothing else, so the FILL: half the user filled in survives byte-for-byte and the Project
    # Facts follow the project.
    #
    # `--client codex` ON THE FACTS CALL IS LOAD-BEARING AND IT IS NOT SYMMETRY. The region is
    # client-conditional: it names the `Skill` tool for Claude Code and says to read the SKILL.md for
    # Codex, because Codex has no skill tool. Dropping the flag here would write the wrong client's
    # sentence into the one document Codex injects whole, on every re-install, and the file would
    # stop matching what a fresh install produces.
    #
    # THE MERGE'S STATUS IS READ, AND THE READ-ONLY CASE GETS ITS OWN SENTENCE AND ITS OWN BRANCH.
    # `mv` onto a file with no write bit prompts on a tty and exits 1 when the prompt is declined; a
    # first version of this arm ignored that and printed `ok Refreshed …` over a file it had not
    # touched, with a receipt row carrying the stale sha. The function refuses before writing anything
    # now — see its header for the pty measurement — and rc 2 means exactly that refusal, which is a
    # state the user clears in one command rather than a failure they debug.
    # Beside the destination — see `mktemp_beside`. This one is the merge's facts file, and
    # `merge_marked_region` derives its own temp from the TARGET, so both renames stay renames.
    TMP_AG=$(mktemp_beside "$PROJECT_DIR" .kinglet-agents-md)
    AG_MERGE_RC=0
    if bash "$GEN" --facts-only --client codex ${GEN_ARGS[@]+"${GEN_ARGS[@]}"} "$PROJECT_DIR" > "$TMP_AG" 2>/dev/null; then
      merge_marked_region "$AGENTS_MD" "$TMP_AG" || AG_MERGE_RC=$?
    else
      AG_MERGE_RC=1
    fi
    if [ "$AG_MERGE_RC" -eq 0 ]; then
      ok "Refreshed the generated section of AGENTS.md (your prose untouched)"
      AGENTS_BRANCH=refreshed
    elif [ "$AG_MERGE_RC" -eq 2 ]; then
      warn "AGENTS.md is read-only, so its generated section was NOT refreshed and nothing was written."
      warn "Make it writable (under Perforce: check it out) and re-run install.sh --client codex."
      AGENTS_BRANCH=refresh-failed
      note_not_done "AGENTS.md — the file is read-only, so its generated section was NOT refreshed and this project's Codex entry document still carries the facts of an earlier run. Your own prose was not touched. Make it writable (under Perforce: check it out) and re-run install.sh --client codex."
    else
      warn "AGENTS.md refresh failed — left as-is."
      AGENTS_BRANCH=refresh-failed
      note_not_done "AGENTS.md — the generated section could not be refreshed, so this project's Codex entry document still carries the facts of an earlier run. Your own prose was not touched."
    fi
    rm -f "$TMP_AG"
  elif [ -e "$AGENTS_MD" ] && ! owned_by_installer 'AGENTS.md' '' \
       && [ "$AGENTS_MARKER_STATE" != none ] && [ "$AGENTS_MARKER_STATE" != absent ] \
       && [ "$AGENTS_MARKER_STATE" != wellformed ]; then
    # DECLINE, DO NOT REPAIR — CLAUDE.md's ruling, reached through CLAUDE.md's functions. A pair this
    # installer cannot bound is a region boundary it would be guessing at, and the guess is applied
    # to the document Codex injects whole. `absent` is excluded because a directory at this path
    # reports `absent` and must not be diagnosed as a marker fault.
    #
    # `wellformed` IS EXCLUDED TOO, AND THE FIRST VERSION OF THIS ARM DID NOT EXCLUDE IT — measured,
    # not foreseen. The arm above requires the pair AND a previous receipt row; a hand-written
    # AGENTS.md of the user's own that happens to carry a well-formed pair fails only the second
    # test, and it then fell through to here and was told its markers "do not form exactly one
    # begin/end pair" — a diagnosis that is false of the file in front of them, about a fault they do
    # not have. It belongs in the keep arm below, which is what "we have never written this file"
    # means whatever is inside it. The same shape as `malformed-same-line` one file over: the action
    # was right and the sentence was not.
    warn "AGENTS.md — $(marked_region_problem "$AGENTS_MARKER_STATE"), so it was NOT touched."
    warn "$(marked_region_remedy "$AGENTS_MARKER_STATE" AGENTS.md 'install.sh --client codex')"
    AGENTS_BRANCH=malformed
    note_not_done "AGENTS.md — $(marked_region_problem "$AGENTS_MARKER_STATE"), so the generated block was NOT refreshed and your file was left exactly as it was. $(marked_region_remedy "$AGENTS_MARKER_STATE" AGENTS.md 'install.sh --client codex')"
  elif [ -e "$AGENTS_MD" ] && ! owned_by_installer 'AGENTS.md' ''; then
    warn "AGENTS.md exists and is not ours — keeping yours, untouched."
    warn "No Codex entry document was generated this run. Rename or delete AGENTS.md and re-run"
    warn "to get one."
    AGENTS_BRANCH=kept-yours
    note_not_done "AGENTS.md — yours was kept, so this run generated no Codex entry document. Rename or delete it and re-run with --client codex to get one."
  elif ! can_replace "$AGENTS_MD"; then
    # THE WRITE ARM'S HALF OF THE READ-ONLY CONDITION, and it reached here as an abort until
    # 2026-08-17 — see `can_replace`'s header for the pty measurement. The file is ours and unchanged;
    # we simply cannot write it, so say that and carry on with the rest of the install rather than
    # dying at the `mv` with the payload already on disk.
    warn "AGENTS.md is read-only, so it was NOT regenerated and nothing was written."
    warn "Make it writable (under Perforce: check it out) and re-run install.sh --client codex."
    AGENTS_BRANCH=read-only
    note_not_done "AGENTS.md — the file is read-only, so this run did not regenerate it and it still carries an earlier run's content. Make it writable (under Perforce: check it out) and re-run install.sh --client codex."
  else
    # Beside the destination — see `mktemp_beside`.
    TMP_AG=$(mktemp_beside "$PROJECT_DIR" .kinglet-agents-md)
    if bash "$GEN" --client codex ${GEN_ARGS[@]+"${GEN_ARGS[@]}"} "$PROJECT_DIR" > "$TMP_AG" 2>/dev/null; then
      # THE STATUS, FOR THE REASON `can_replace`'s HEADER NOW GIVES. That predicate answers for the
      # FILE and this answers for everything else — measured (W1) in a project directory at 555 with a
      # writable AGENTS.md of ours: `can_replace` says yes, the rename fails, and as a bare command it
      # ended the whole install at rc 1 with the payload already on disk.
      if mv "$TMP_AG" "$AGENTS_MD"; then
        # `mv` from mktemp carries 0600 across; the receipt row reads the mode off the file, so this
        # keeps the file readable AND keeps the row honest rather than hardcoding a mode.
        chmod 644 "$AGENTS_MD"
        ok "Generated AGENTS.md (the Codex entry document)"
        AGENTS_BRANCH=written
      else
        rm -f "$TMP_AG"
        warn "AGENTS.md could not be written — the rename into place failed, so it was left as it was."
        AGENTS_BRANCH=write-failed
        # ONE SENTENCE FOR BOTH STATES, because this arm cannot promise which one it is in and a
        # branch value per state would be a third token for one outcome. An earlier run's document may
        # be sitting there untouched, or there may be none at all; the entry says so rather than
        # asserting the worse case, which is what `generation failed` above does correctly for a path
        # where nothing can have been written.
        note_not_done "AGENTS.md — the rename into place failed, so this run did not write it. If an earlier run wrote one it is still there, unchanged and a version behind; if not, this project has no Codex entry document and none of the toolkit's conventions reach a Codex session."
      fi
    else
      rm -f "$TMP_AG"
      warn "AGENTS.md generation failed — skipped."
      note_not_done "AGENTS.md — generation failed, so this project has no Codex entry document and none of the toolkit's conventions reach a Codex session."
    fi
  fi
  # Outside the branch, for the reason every root-file row in this installer is: on a re-install
  # where the file is ours and unchanged the writing branch still runs, but on a run where it was
  # kept the row must not appear, and `owned_by_installer` is the only thing that can tell them
  # apart. There is no reference copy — the document is generated per project — so the ref is ''.
  #
  # THE SECOND ROW SHAPE, AND IT IS THE HALF THAT ENDS THE SILENCE. A refreshed AGENTS.md is part
  # ours and part the user's, so a `toolkit` row would be a claim `uninstall.sh` acts on — it would
  # delete the prose the installer told the user to write. `user-modified` is the vocabulary that
  # already exists for exactly this: uninstall.sh reports it under `keep N file(s) you modified` and
  # leaves it, `--purge` still removes it, `studio-doctor.sh` counts it under `modified since
  # install` BY NAME, and install.sh's own MODIFIED_FILES loop lists it under `keeping yours` on
  # every later run. That is the whole of the asymmetry Task 12 measured against a frozen skill, and
  # it is closed by writing the row rather than by arguing about it.
  #
  # IT IS FAIL-CLOSED THROUGH TWO TESTS, AND THE SECOND ONE ARRIVED FROM A MEASUREMENT. A
  # `user-modified` row is still a claim of ownership and `--purge` acts on every claim — this file's
  # own ownership header says so. The row therefore needs evidence, and `receipt_has` alone is not
  # enough: it answers *"did a run of ours ever write this PATH"*, not *"is this the FILE we wrote"*.
  # Four adversarial shapes were built; the one that separates them is a user who deletes our document
  # and puts their own, marker-less file at the same path. `receipt_has` still says yes, and the run
  # says `AGENTS.md exists and is not ours — keeping yours, untouched` while a row underneath it hands
  # `--purge` a file with not one byte of ours in it. That is the false-reassurance pair this file
  # already records at its unreadable-origins block — *"a sentence that tells the user a file is
  # unclaimed, immediately before claiming it"* — and it also made two states print identical output
  # with opposite `--purge` outcomes.
  #
  # SO THE SECOND TEST IS THE MARKER PAIR, AND IT IS EVIDENCE RATHER THAN PROOF. The user did not
  # invent `kinglet:generated`; we wrote it, so a file still carrying it — well formed, or damaged in
  # a way this installer declines to bound — is *most likely* the document we generated with the
  # user's work in it. A file with no pair at all is theirs, whatever the path once held, and gets no
  # row: `--purge` cannot reach it and the `keeping yours, untouched` sentence stays true.
  #
  # IT IS NOT PROOF, AND THE FIRST VERSION OF THIS PARAGRAPH SAID *"is the document we generated"*
  # FLATLY. Measured: a file of the user's own, at a path a run of ours once wrote, that merely quotes
  # one `kinglet:generated:begin` line satisfies this test and gets a row that `--purge` acts on. The
  # test narrows the previous condition rather than closing it — before it, EVERY file at such a path
  # got the row, marker or not — and closing it properly needs something this installer does not have:
  # a way to tell a document that descends from ours from one that merely looks like it. Recorded
  # rather than claimed away.
  #
  # AND THE DESTRUCTIVE MEMBER, WHICH THIS PARAGRAPH RECORDED ONLY THE HARMLESS HALF OF. The example
  # above costs a row on a file the installer declines to touch. The one that costs work is a
  # user's own document that **documents** these markers — a `:begin` and an `:end` quoted in a fenced
  # code block, in order. `marked_region_state`'s awk is unanchored, so that file is `wellformed`;
  # with a path we once wrote, the refresh arm merges into it, replaces whatever sat between their
  # two quoted lines with the generated facts, and prints `your prose untouched` while doing it.
  # That is the pre-existing well-formed-coincidence merge (routed to the ledger), and it is what
  # this criterion admits, so it belongs in the same paragraph as the harmless case rather than one
  # document away.
  #
  # This is the same shape as `owned_by_installer`'s two disjuncts — evidence in the file, or evidence
  # in the receipt — with the file half being the marker pair rather than a checksum, because a
  # per-project generated document has no shipped copy to compare against.
  #
  # `refreshed` IS NOT ADDED TO THE `written` DISJUNCT. That arm writes a `toolkit` row, and a
  # refreshed file is not toolkit-owned. Reading the two as one branch — "we wrote to it, so it is
  # ours" — is authorship, and this file's header is about the difference.
  if [ "$AGENTS_BRANCH" = written ] || owned_by_installer 'AGENTS.md' ''; then
    printf 'AGENTS.md\t%s\t%s\ttoolkit\n' \
      "$(sha_of "$AGENTS_MD")" \
      "$(stat -c '%a' "$AGENTS_MD" 2>/dev/null || echo 644)" >> "$RECEIPT_TMP"
  elif [ "$AGENTS_WAS_OURS" -eq 1 ] && [ -f "$AGENTS_MD" ] \
       && [ "$AGENTS_MARKER_STATE" != none ] && [ "$AGENTS_MARKER_STATE" != absent ]; then
    # EVERY BRANCH THAT KEEPS A FILE STILL CARRYING OUR MARKERS, AND THE CONDITION NAMES NO BRANCH.
    # Refreshed, refresh-failed and declined-as-malformed all land here — each is a document we wrote,
    # with the user's work in it, that this run could not or would not replace, and being unrecorded
    # is exactly the state the task exists to end. A branch list would be a second enumeration to keep
    # in step with the block above; what the row is about is the FILE.
    printf 'AGENTS.md\t%s\t%s\tuser-modified\n' \
      "$(sha_of "$AGENTS_MD")" \
      "$(stat -c '%a' "$AGENTS_MD" 2>/dev/null || echo 644)" >> "$RECEIPT_TMP"
  fi

  # ── 8d.2 the skill root ─────────────────────────────────────────────────
  # Measured: `.claude/skills/` unaided gives Codex ZERO skills, and so does the `skills` config key
  # under both spellings. A root at `.agents/skills/` holding one symlink per skill gives all of
  # them, enabled, with invocation observed — and every symlinked entry reports the REAL
  # `.claude/skills/<name>/SKILL.md` as its path, so the link is a discovery device and not a second
  # copy. That is why this is `ln -s` and not `cp`: a copy discovers the same set and then goes
  # stale the moment a skill is edited.
  #
  # PER-ENTRY, NOT ONE DIRECTORY SYMLINK, because row 3 below writes generated command skills into
  # this same root and a directory symlink has nowhere to put them. The mixed root was measured
  # rather than assumed: 17 repo-scope skills, all enabled, errors [].
  # `.agents/` IS ONE OF THE FOUR DIRECTORIES THE WRITE CLASS'S CRITERION NAMES, AND THIS BLOCK'S
  # THREE WRITES WERE ALL BARE UNTIL 2026-08-17. Measured on the class's own trigger — a VCS holding
  # an unopened file read-only, which is every submitted file on a Perforce-managed project:
  #
  #   `chmod 444 .agents/skills/unity-init/SKILL.md`, re-install  →  `cp: cannot create regular
  #     file …: Permission denied`, **rc 1**, after AGENTS.md and the 16 skill links had landed and
  #     before `.codex/hooks.json` and `.codex/config.toml`;
  #   `chmod 555 .agents/skills`, remove one link, re-install     →  `ln: failed to create symbolic
  #     link …: Permission denied`, **rc 1**.
  #
  # `is_modified` cannot see a mode change, so a read-only-but-unedited converted skill takes the
  # `cp` arm every time. Both now count the failure and let the run finish; the counts are what the
  # report is built from, so one sealed directory produces one line rather than seventeen.
  SKILLS_LINKED=0; SKILLS_KEPT=0; SKILLS_FAILED=0
  # `|| true` on the directory itself, not a status read: when it fails every `ln -s` below fails
  # too, and the count those produce names the same cause with the number attached.
  mkdir -p "$CODEX_SKILL_ROOT" 2>/dev/null || true
  for sd in "$CLAUDE_DIR"/skills/*/; do
    [ -d "$sd" ] || continue
    sname=$(basename "$sd")
    slink="$CODEX_SKILL_ROOT/$sname"
    # RELATIVE, so the root survives the project being moved or renamed. The hook config cannot be
    # relative — Codex runs those commands from elsewhere — but a skill root is read in place.
    swant="../../.claude/skills/$sname"
    if [ -L "$slink" ]; then
      if [ "$(readlink "$slink")" != "$swant" ]; then
        # Someone else's link at our path. Same rule as every other file: not ours, not touched,
        # and no row, so uninstall.sh will never take it either.
        SKILLS_KEPT=$((SKILLS_KEPT + 1))
        continue
      fi
    elif [ -e "$slink" ]; then
      SKILLS_KEPT=$((SKILLS_KEPT + 1))
      continue
    else
      # NO ROW EITHER, WHICH IS WHY THIS `continue`S RATHER THAN COUNTING AND CARRYING ON: the
      # `printf` below records `.agents/skills/<name>` as ours, and a row for a link that was never
      # created is a row `uninstall.sh` acts on by removing whatever ends up at that path later.
      if ! ln -s "$swant" "$slink" 2>/dev/null; then
        SKILLS_FAILED=$((SKILLS_FAILED + 1))
        continue
      fi
    fi
    SKILLS_LINKED=$((SKILLS_LINKED + 1))
    # MODE `symlink`, AND THE CHECKSUM COLUMN CARRIES THE TARGET. A symlink to a directory has no
    # sha256 — `sha_of` returns the empty string for it, and an empty checksum is a row uninstall.sh
    # silently declines to act on, which reads as coverage and is not. The target is what the row
    # actually has to vouch for: uninstall removes the link only while it still points where we
    # pointed it.
    printf '.agents/skills/%s\t%s\tsymlink\ttoolkit\n' "$sname" "$swant" >> "$RECEIPT_TMP"
  done
  # A skill this payload no longer ships leaves a dangling entry behind, and Codex lists what it can
  # resolve and says nothing about the rest — so a dangling entry is invisible rather than noisy.
  # Only OUR links are pruned, identified by the SAME equality the link loop uses — the target must
  # be exactly `../../.claude/skills/<the link's own name>` — and only when that skill is gone:
  # anything else in this directory belongs to someone else.
  SKILLS_PRUNED=0; SKILLS_PRUNE_FAILED=0
  for slink in "$CODEX_SKILL_ROOT"/*; do
    [ -L "$slink" ] || continue
    sname=$(basename "$slink")
    starget="$(readlink "$slink")"
    # THE LINK LOOP'S OWNERSHIP TEST, SPELLED THE SAME WAY, AND THAT IS THE WHOLE FIX.
    #
    # This was `case "$starget" in ../../.claude/skills/*)` — a PREFIX where the loop above uses an
    # EQUALITY against `../../.claude/skills/$sname`. A prefix is strictly weaker, so the two loops
    # disagreed about exactly one shape: a link whose NAME is a payload skill's and whose TARGET is
    # some other skill. The loop above calls that "not ours" and leaves it; this loop called it ours
    # and deleted it.
    #
    # Measured 2026-09-08, before this change, in ONE run on one fixture:
    #
    #     ok  Skill root: 15 link(s) in .agents/skills/, 1 pruned
    #     warn 1 entr(ies) in .agents/skills/ are not ours — left alone, ...
    #     -> the link was DELETED
    #
    # "Left alone" and the deletion, in the same breath. That is the worst shape available for it:
    # the output tells the user the file was kept, so nothing invites them to look, and a link they
    # placed on purpose is gone silently. Two readers of one ownership question, in the one place
    # where the answer decides whether a user's file is deleted — so they are now one reader.
    #
    # The prune itself is unchanged in what it exists for: OUR link, for a skill the payload no
    # longer ships, still goes. `tests/test-install-prune.sh` pins both directions, and the control
    # is the half that matters — without it these assertions pass under a prune that does nothing.
    if [ "$starget" = "../../.claude/skills/$sname" ]; then
        if [ ! -d "$CLAUDE_DIR/skills/$sname" ]; then
          # THE DELETE READS ITS STATUS FOR THE SAME REASON THE TWO CREATES DO. `rm -f` is silent
          # about a missing file and NOT about a directory that refuses the unlink, so on a sealed
          # `.agents/skills/` this was an abort — and this loop runs after the links and rows above
          # have already landed, so the abort would leave the receipt describing more than the run
          # finished.
          if rm -f "$slink" 2>/dev/null; then
            SKILLS_PRUNED=$((SKILLS_PRUNED + 1))
          else
            SKILLS_PRUNE_FAILED=$((SKILLS_PRUNE_FAILED + 1))
            # THE ROW SURVIVES THE FAILED PRUNE, AND THIS IS THE SAME DEFECT AS `.codex/hooks.json`'S
            # ONE ARM OVER. That row states what we OWN at the end of the run, not what this run
            # wrote — and the moment a delete gained a failure arm, the row for the path it could not
            # delete stopped being written at all. The link is not in the loop above (its skill is no
            # longer in the payload, which is why it is a prune candidate), so nothing else can write
            # it. Measured 2026-08-17: 1 row before, **0** after, the link still on disk, and
            # `uninstall.sh --yes` walking past it — a link of ours that nothing can now remove.
            #
            # THE EQUALITY ABOVE IS THE OWNERSHIP TEST, and it is the one the link loop already
            # trusts. It admits only a link pointing exactly where we point ours, and on that
            # evidence alone this block is willing to DELETE the link; recording a row for one it
            # failed to delete is strictly weaker than deleting it, and it is what lets
            # `uninstall.sh` finish the job the seal prevented.
            printf '.agents/skills/%s\t%s\tsymlink\ttoolkit\n' \
              "$(basename "$slink")" "$starget" >> "$RECEIPT_TMP"
          fi
        fi
    fi
  done
  ok "Skill root: $SKILLS_LINKED link(s) in .agents/skills/$([ "$SKILLS_PRUNED" -gt 0 ] && printf ', %s pruned' "$SKILLS_PRUNED")"
  if [ "$SKILLS_KEPT" -gt 0 ]; then
    warn "$SKILLS_KEPT entr(ies) in .agents/skills/ are not ours — left alone, so those skills may not reach Codex."
    note_not_done "$SKILLS_KEPT entr(ies) in .agents/skills/ were already there and are not ours, so this run did not link those skills. Remove them and re-run if you want Kinglet's copies."
  fi
  if [ "$SKILLS_FAILED" -gt 0 ]; then
    warn "$SKILLS_FAILED skill link(s) could not be created — .agents/skills/ would not take them."
    note_not_done "$SKILLS_FAILED of the toolkit's skills could not be linked into .agents/skills/, so a Codex session in this project cannot reach them and no receipt row claims them. Check that .agents/skills/ is writable (under Perforce: check the directory out) and re-run install.sh --client codex."
  fi
  if [ "$SKILLS_PRUNE_FAILED" -gt 0 ]; then
    warn "$SKILLS_PRUNE_FAILED stale skill link(s) in .agents/skills/ could not be removed."
    note_not_done "$SKILLS_PRUNE_FAILED link(s) in .agents/skills/ point at skills this payload no longer ships and could not be removed, so Codex sees entries that resolve to nothing and says so nowhere. Delete them by hand, or make .agents/skills/ writable and re-run install.sh --client codex."
  fi

  # ── 8d.3 the commands, converted ────────────────────────────────────────
  # Codex has no command surface at all — 24 subcommands, none a prompt registry — so Kinglet's nine
  # commands reach a Codex reader only as skills. Its own importer converts two of the nine and
  # drops the other seven silently on an `$ARGUMENTS` token, reporting zero failures; with no
  # converter, nine of nine are lost.
  #
  # WRITTEN THROUGH A TEMP DIRECTORY AND THEN THE PAYLOAD LOOP'S OWN GUARD, rather than letting the
  # converter write into the project directly. The converter overwrites; `is_modified` is what makes
  # "the user edited this" survive an upgrade, and it is the same test, spelled the same way, that
  # both write loops in Step 5 use. Skipping it here would make these the only files in the tree an
  # upgrade destroys.
  CMDSKILL_W=0; CMDSKILL_K=0; CMDSKILL_F=0
  CONV="$CLAUDE_DIR/scripts/codex-command-to-skill.sh"
  if [ -f "$CONV" ]; then
    CONV_TMP=$(mktemp -d)
    if bash "$CONV" --project-dir "$PROJECT_DIR" --out "$CONV_TMP" >/dev/null 2>&1; then
      while IFS= read -r cf; do
        [ -n "$cf" ] || continue
        crel=".agents/skills/${cf#"$CONV_TMP"/}"
        cdest="$PROJECT_DIR/$crel"
        if is_modified "$crel"; then
          CMDSKILL_K=$((CMDSKILL_K + 1))
          printf '%s\t%s\t%s\tuser-modified\n' "$crel" "$(sha_of "$cdest")" \
            "$(stat -c '%a' "$cdest" 2>/dev/null || echo 644)" >> "$RECEIPT_TMP"
          continue
        fi
        # THE COPY'S STATUS. `is_modified` compares CONTENT, so a converted skill a VCS is holding
        # read-only and nobody has edited is not modified: this arm takes it, and until 2026-08-17
        # the bare `cp` then ended the run at rc 1 with the links and AGENTS.md already written and
        # `.codex/` not yet. Counted rather than fatal now.
        #
        # AND THE ROW IS OUTSIDE THE WRITE, WHICH THE FIRST VERSION OF THIS ARM GOT BACKWARDS. It
        # `continue`d past the row on failure and argued *"no `toolkit` row is written for a file
        # this run did not put there"* — true of a path nothing has ever written, and FALSE of this
        # one, where an earlier run of ours wrote the file and this run merely declined to rewrite
        # it. Measured 2026-08-17 on the state `tests/test-install-not-done.sh` B.7f already builds:
        # 1 row before, **0** after, the file still on disk unedited and ours, and `uninstall.sh
        # --yes` leaving it behind. That is the same leak this commit's sibling paragraph diagnosed
        # for `.codex/hooks.json`, created one screen away by the same mechanism — a refusal added
        # around a row that was inside the write.
        #
        # SO THE TEST IS OWNERSHIP AT THE END OF THE RUN, in the two disjuncts `.codex/hooks.json`
        # uses: this run's own knowledge (we just wrote it), or `owned_by_installer`. `[ -f ]` is
        # what keeps the other direction closed — a `cp` that failed with nothing at the path, which
        # is B.7c's sealed-root state, still gets no row, and neither does a link that was never
        # created.
        mkdir -p "$(dirname "$cdest")" 2>/dev/null || true
        cmd_wrote=0
        if cp "$cf" "$cdest" 2>/dev/null; then
          CMDSKILL_W=$((CMDSKILL_W + 1)); cmd_wrote=1
        else
          CMDSKILL_F=$((CMDSKILL_F + 1))
        fi
        if [ -f "$cdest" ] && { [ "$cmd_wrote" -eq 1 ] || owned_by_installer "$crel" "$cf"; }; then
          printf '%s\t%s\t%s\ttoolkit\n' "$crel" "$(sha_of "$cdest")" \
            "$(stat -c '%a' "$cdest" 2>/dev/null || echo 644)" >> "$RECEIPT_TMP"
        fi
      done <<< "$(find "$CONV_TMP" -type f 2>/dev/null | sort)"
      ok "Converted $CMDSKILL_W command(s) into .agents/skills/$([ "$CMDSKILL_K" -gt 0 ] && printf ', kept %s of yours' "$CMDSKILL_K")"
      # ── 8d.3b retired commands: prune the skills they left behind ─────────
      # A command this payload no longer ships leaves its converted skill on disk forever, AND the
      # row for it is not rewritten -- the loop above only visits what the converter just produced.
      # So the file stayed and the receipt stopped claiming it: an orphan `uninstall.sh` cannot take
      # either. Measured 2026-09-08 on a fixture before this block existed -- plant
      # `.agents/skills/unity-retired/SKILL.md` with a toolkit row, re-run, and the file is still
      # there with zero rows naming it. Same leak two earlier rounds of this wave repaired elsewhere.
      #
      # THREE THINGS DECIDE WHAT GOES, and each is a way this could delete a user's directory:
      #
      #   1. INSIDE the converter's success branch. A converter that failed produces an empty
      #      CONV_TMP, and "nothing was converted" would read as "everything was retired". Absence is
      #      not retirement, and putting the block here makes that structural instead of a check.
      #   2. Only names the PREVIOUS receipt claimed as `toolkit`. Ownership is read from the
      #      receipt, never from the mode bits: a directory under this root that no row of ours ever
      #      named is somebody else's and is not ours to remove. That is also the standing limit of
      #      this repair -- a skill orphaned by the defect ITSELF lost its row, so nothing can now
      #      prove it was ours and it stays. `uninstall.sh --purge` and a re-install is the clean
      #      route for those, and it is stated rather than guessed at.
      #   3. Unmodified, by `is_modified`, file by file. A retired command the user edited is theirs.
      #      Its rows are carried forward as `user-modified` so the file keeps an owner and
      #      `uninstall.sh` still reports it, rather than being silently dropped a second time.
      CMDSKILL_P=0; CMDSKILL_PF=0; CMDSKILL_PK=0
      if [ -f "$RECEIPT" ]; then
        CMDSKILL_LIVE=""
        for cdir in "$CONV_TMP"/*/; do
          [ -d "$cdir" ] || continue
          CMDSKILL_LIVE="$CMDSKILL_LIVE$(basename "$cdir")
"
        done
        CMDSKILL_PREV="$(awk -F'\t' '$1 ~ /^\.agents\/skills\/[^\/]+\// && $4 == "toolkit" { split($1, g, "/"); print g[3] }' < "$RECEIPT" 2>/dev/null | sort -u)"

        while IFS= read -r cretired; do
          [ -n "$cretired" ] || continue
          # A here-string, not a pipe: `grep -q` exits on its first match without draining stdin, and
          # under `set -euo pipefail` that SIGPIPEs the writer on a long list.
          if grep -qxF -- "$cretired" <<< "$CMDSKILL_LIVE"; then continue; fi

          cret_dir="$PROJECT_DIR/.agents/skills/$cretired"
          [ -d "$cret_dir" ] || continue
          cret_rows="$(awk -F'\t' -v n="$cretired" 'index($1, ".agents/skills/" n "/") == 1 { print $1 }' < "$RECEIPT" 2>/dev/null)"

          cret_edited=0
          while IFS= read -r cret_rel; do
            [ -n "$cret_rel" ] || continue
            if is_modified "$cret_rel"; then cret_edited=1; fi
          done <<< "$cret_rows"

          if [ "$cret_edited" -eq 1 ]; then
            CMDSKILL_PK=$((CMDSKILL_PK + 1))
            while IFS= read -r cret_rel; do
              [ -n "$cret_rel" ] || continue
              [ -f "$PROJECT_DIR/$cret_rel" ] || continue
              printf '%s\t%s\t%s\tuser-modified\n' "$cret_rel" \
                "$(sha_of "$PROJECT_DIR/$cret_rel")" \
                "$(stat -c '%a' "$PROJECT_DIR/$cret_rel" 2>/dev/null || echo 644)" >> "$RECEIPT_TMP"
            done <<< "$cret_rows"
            continue
          fi

          if rm -rf "$cret_dir" 2>/dev/null; then
            CMDSKILL_P=$((CMDSKILL_P + 1))
          else
            CMDSKILL_PF=$((CMDSKILL_PF + 1))
          fi
        done <<< "$CMDSKILL_PREV"
      fi
      if [ "$CMDSKILL_P" -gt 0 ] || [ "$CMDSKILL_PK" -gt 0 ]; then
        ok "Retired command skills: $CMDSKILL_P removed from .agents/skills/$([ "$CMDSKILL_PK" -gt 0 ] && printf ', %s kept because you edited them' "$CMDSKILL_PK")"
      fi
      if [ "$CMDSKILL_PF" -gt 0 ]; then
        warn "$CMDSKILL_PF retired command skill(s) in .agents/skills/ could not be removed."
        note_not_done "$CMDSKILL_PF converted command skill(s) for commands this payload no longer ships are still in .agents/skills/ and could not be removed, so a Codex session still lists them and they resolve to guidance the toolkit has retired. Make .agents/skills/ writable (under Perforce: check it out) and re-run install.sh --client codex, or delete them by hand."
      fi

      if [ "$CMDSKILL_F" -gt 0 ]; then
        warn "$CMDSKILL_F converted command skill(s) could not be written into .agents/skills/."
        note_not_done "$CMDSKILL_F of the converted command skills could not be written into .agents/skills/ — the file or its directory is read-only — so under Codex those Unity diagnostics are either absent or a version behind. Whichever of ours is still at that path keeps its receipt row, so uninstall.sh can still take it. Make .agents/skills/ and its contents writable (under Perforce: check them out) and re-run install.sh --client codex."
      fi
    else
      warn "codex-command-to-skill.sh failed — the commands did not cross to Codex."
      # 1023 IS DERIVED — `cat .claude/commands/*.md | wc -l` — AND IT IS GUARDED. It read 919 until
      # 2026-08-16, which was correct until Task 8 added 63 lines to unity-doctor.md inside the same
      # wave; that task corrected the research document and left this string, which is the half a
      # user reads. tests/test-derived-counts.sh's tree-size block now reds when the two disagree.
      note_not_done "The nine commands were NOT converted into .agents/skills/, so 1023 lines of Unity diagnostics that exist nowhere else in the toolkit are unreachable under Codex. Run .claude/scripts/codex-command-to-skill.sh by hand to see why it failed."
    fi
    rm -rf "$CONV_TMP"
  fi

  # ── 8d.4 .codex/hooks.json ──────────────────────────────────────────────
  # EVERY ARM HERE IS A REFUSAL BEFORE THE HOOK CONFIG IS REPLACED, and each closes a measured way to
  # end up with a config that registers and enforces nothing. It read *"before a byte is written"*
  # until 2026-08-17, and the commit that moved the temp into `.codex/` — for the atomicity the
  # rename depends on — falsified it in the same diff: the shim writes ~5.4 kB into
  # `.codex/.hooks.json.XXXXXX` before the read-only arm below refuses anything, and on a space-
  # limited `.codex/` that write is exactly what runs out of room. Bytes land in the user's `.codex/`
  # first now; what no arm here does is touch `hooks.json` itself before deciding. The number of arms
  # is deliberately not written down:
  # this comment read `THREE REFUSALS` from the day the block was built, and the count has moved
  # twice since — once when the read-only check arrived, once when `.codex/` itself became a skip
  # reason instead of an abort — with the sentence carried forward as context both times. Read the
  # arms; they are all in this one `if`/`elif` chain and the `if`/`elif` inside its `else`.
  #
  # THE DIRECTORY IS A WRITE TOO, AND IT WAS BARE. `.codex/` is one of the four the write class's
  # criterion names; on a sealed project root this `mkdir -p` ended the run at rc 1, after AGENTS.md
  # and the skill root had landed. It becomes the fourth skip reason rather than an abort, so the
  # cause is named once and `.codex/config.toml` below reports its own half in its own words.
  CODEX_DIR_OK=1
  mkdir -p "$CODEX_DIR" 2>/dev/null || CODEX_DIR_OK=0
  CODEX_SHIM="$CLAUDE_DIR/scripts/codex-hook-shim.sh"
  HOOKS_JSON_OK=0
  HOOKS_SKIP_WHY=""
  case "$PROJECT_DIR" in
    # `--emit-config` single-quotes paths without escaping, so one apostrophe in the project path
    # produces a config Codex parses wrongly. Codex's own importer has the same shape, so this is
    # parity rather than regression — and a broken config is still a silent allow, so it is refused
    # rather than emitted.
    *\'*) HOOKS_SKIP_WHY="the project path contains a single quote, which --emit-config cannot escape" ;;
  esac
  if [ -z "$HOOKS_SKIP_WHY" ] && [ "$CODEX_DIR_OK" -eq 0 ]; then
    HOOKS_SKIP_WHY=".codex/ does not exist and could not be created — the project root would not take it"
  fi
  if [ -z "$HOOKS_SKIP_WHY" ] && [ ! -f "$CODEX_SHIM" ]; then
    # THE ORDERING SELF-CHECK. Unreachable while Step 5 runs first, which is the point: it makes the
    # ordering an invariant this file enforces rather than one a reviewer has to notice.
    HOOKS_SKIP_WHY="the shim is not in the project at $CODEX_SHIM — the hook config's command strings are absolute, so emitting one now would point every hook at this toolkit checkout"
  fi
  if [ -z "$HOOKS_SKIP_WHY" ] && ! command -v jq >/dev/null 2>&1; then
    HOOKS_SKIP_WHY="jq is not on PATH, and every Kinglet hook needs it"
  fi
  if [ -n "$HOOKS_SKIP_WHY" ]; then
    warn "Codex hook config not written: $HOOKS_SKIP_WHY."
    note_not_done "The Codex hook config was NOT written — $HOOKS_SKIP_WHY. Under Codex a project with the skills bridge and no .codex/hooks.json is advisory rather than enforcing, and nothing inside the session says so."
  elif [ -e "$CODEX_HOOKS_JSON" ] && ! owned_by_installer '.codex/hooks.json' ''; then
    warn ".codex/hooks.json exists and is not ours — keeping yours, untouched."
    warn "It was not regenerated, so it may not match .claude/settings.json."
    note_not_done ".codex/hooks.json — yours was kept, so the hook config was not regenerated from this version's .claude/settings.json. Delete it and re-run to get a generated one."
  else
    # BESIDE THE DESTINATION — see `mktemp_beside`. `mktemp` alone put this in `$TMPDIR`, and the
    # rename below is `rename(2)` only within one filesystem, so the atomicity the comment further
    # down claims held on the host it was written on and nowhere else. Measured 2026-08-17 with
    # `$TMPDIR` on another filesystem and the real 5429-byte config as the destination: an
    # interrupted cross-device `mv` left 4096 bytes that `jq` refuses — a silent ALLOW — while this
    # block printed *"untouched rather than half-written"*.
    HCFG_TMP=$(mktemp_beside "$CODEX_DIR" .hooks.json)
    if bash "$CODEX_SHIM" --emit-config --project-dir "$PROJECT_DIR" > "$HCFG_TMP" 2>/dev/null; then
      HCFG_DEFECTS="$(codex_config_defects "$HCFG_TMP")"
      if [ -z "$HCFG_DEFECTS" ]; then
        # THE REFUSAL THAT WAS MISSING FROM A BLOCK BUILT OUT OF REFUSALS — the last one added, not
        # the fourth one: see this block's header for why no ordinal is written here. This
        # write was `cat "$HCFG_TMP" > "$CODEX_HOOKS_JSON"`: truncating, non-atomic, and unread.
        # Measured 2026-08-17 with a read-only `.codex/hooks.json` of ours — the state a VCS puts
        # every unopened file in — it died with `Permission denied` and `set -e` ended the run at
        # **rc 1**, mid-Codex-layer, immediately after AGENTS.md had been regenerated.
        #
        # WORSE THAN ANY OF THE `mv` SITES, WHICH IS WHY IT MOVED TO A RENAME RATHER THAN GAINING A
        # STATUS TEST ALONE. A truncating write that fails AFTER the open — ENOSPC, an I/O error —
        # leaves a half-written hook config on disk. Codex cannot parse that, and per this block's
        # own header an unparseable config is a silent ALLOW: the exact outcome the refusals above it
        # exist to prevent, arriving through the write instead of through the content. The
        # temp file already exists three lines up, so a rename costs nothing and makes the file
        # either the old one or the new one and never half of either — WHICH IS TRUE ONLY BECAUSE
        # THAT TEMP IS NOW CREATED INSIDE `.codex/`. From `$TMPDIR` the same `mv` is a copy on any
        # host where `/tmp` is a tmpfs or the project sits on a second drive, and an interrupted copy
        # is exactly the half-written config this arm exists to make impossible. See `mktemp_beside`.
        #
        # `chmod` BEFORE THE RENAME, not after: `mktemp` gives 0600 and the receipt row reads the
        # mode off the file, so doing it in this order means the row cannot record a mode the file
        # held only briefly.
        if ! can_replace_or_report "$CODEX_HOOKS_JSON" ".codex/hooks.json" "install.sh --client codex"; then
          note_not_done ".codex/hooks.json — the file is read-only, so this run did not regenerate it and it may not match this version's .claude/settings.json. Under Codex a stale hook config enforces whatever it still names and nothing else. Make it writable (under Perforce: check it out) and re-run install.sh --client codex."
        elif chmod 644 "$HCFG_TMP" && mv "$HCFG_TMP" "$CODEX_HOOKS_JSON"; then
          HOOKS_JSON_OK=1
          ok "Wrote .codex/hooks.json (every command routed through the project's own shim)"
        else
          warn ".codex/hooks.json could not be written — the rename into place failed, so the"
          warn "previous config (if any) is untouched rather than half-written."
          note_not_done ".codex/hooks.json — it could not be written, so this project has no hook config from this run and is advisory rather than enforcing under Codex. Check that .codex/ is writable and re-run install.sh --client codex."
        fi
      else
        # NOT INSTALLED, AND SAID ALOUD WITH THE OFFENDING PATHS IN IT. The usual cause is a kept
        # .claude/settings.json registering a hook this version no longer ships: under Claude Code
        # that is a dead registration the block above already reports, and under Codex the same row
        # becomes a command that cannot run, which is an ALLOW. A config nobody can read as broken
        # is worse than no config, because /unity-doctor Check 3b can see a missing file.
        warn "Codex hook config NOT written — it would register command(s) that cannot run:"
        while IFS= read -r hd; do
          if [ -n "$hd" ]; then printf '       %s\n' "$hd"; fi
        done <<< "$HCFG_DEFECTS"
        warn "Under Codex a hook command that cannot run is a silent ALLOW, not an error."
        note_not_done ".codex/hooks.json was NOT written: the config derived from .claude/settings.json $(printf '%s' "$HCFG_DEFECTS" | tr '\n' ';' ). Fix those registrations in .claude/settings.json and re-run with --client codex."
        # And do not leave OUR own stale one behind if it is equally unrunnable. A config that
        # matches nothing on disk is the state this whole branch exists to refuse.
        #
        # THE DELETE READS ITS STATUS, LIKE ITS SIBLING IN 8d.2. It was bare while `rm -f "$slink"`
        # two hundred lines up was given one in the same commit, in a round whose claim was that the
        # class had been re-derived over every write verb — and `rm` is on that list. `rm -f` is
        # silent about a missing file and not about a directory that refuses the unlink, so this was
        # an abort on a `.codex/` that will not take the change. It needs a defective emitted config
        # AND a sealed `.codex/` at once, which is why it is reported rather than given a fixture:
        # the entry names the consequence, and the row below still claims the file so `uninstall.sh`
        # can take away what this run could not.
        if [ -f "$CODEX_HOOKS_JSON" ] && owned_by_installer '.codex/hooks.json' '' \
           && [ -n "$(codex_config_defects "$CODEX_HOOKS_JSON")" ]; then
          if rm -f "$CODEX_HOOKS_JSON" 2>/dev/null; then
            warn "Removed the previous .codex/hooks.json — its commands could not run either."
          else
            warn "The previous .codex/hooks.json could not be removed, and its commands cannot run"
            warn "either — Codex will register them and silently allow every call they should refuse."
            note_not_done ".codex/hooks.json — the previous config could not be removed and its commands cannot run, so Codex registers hooks that allow silently. Delete .codex/hooks.json by hand, or make .codex/ writable and re-run install.sh --client codex."
          fi
        fi
      fi
    else
      warn "codex-hook-shim.sh --emit-config failed — .codex/hooks.json was not written."
      note_not_done ".codex/hooks.json — --emit-config failed, so this project has no Codex hook layer and is advisory rather than enforcing under Codex."
    fi
    rm -f "$HCFG_TMP"
  fi
  # OUTSIDE THE BRANCHES, FOR THE REASON .mcp.json'S ROW AND MCP-SETUP.md'S ROW ARE: the row states
  # what we OWN at the end of the run, not what this run happened to write. It sat inside the success
  # arm, and the moment that block gained refusals the row started disappearing on every one of them.
  # Measured 2026-08-17: install once with `--client codex` (1 row), `chmod 444 .codex/hooks.json`,
  # install again — the refusal fires, the run correctly leaves the file alone, and the new receipt
  # carries **0** rows for it. The file is still ours and still on disk, and `uninstall.sh` — which
  # removes only what the receipt lists — can no longer take it, while `studio-doctor.sh` stops
  # checking it. The keep arms for AGENTS.md two hundred lines up already answer this the same way,
  # and the same reasoning covers the not-ours keep (no row, because it is not ours), the skip
  # reasons, and the defects arm (which deletes an unrunnable config of ours when it can, so `-f`
  # is false — and when it cannot, the file is still there and still ours and this row claims it).
  #
  # AND IT COVERS 8d.2's TWO NEW REFUSAL ARMS, WHICH IT DID NOT WHEN THIS PARAGRAPH WAS WRITTEN. The
  # commit that diagnosed the leak here gave `.agents/` a `cp` refusal and a prune refusal in the
  # same diff and left both rows inside their writes, so both leaked the same way — 1 row → 0, file
  # and link still on disk, `uninstall.sh --yes` walking past them. A class is not closed by fixing
  # the member you were looking at, and this paragraph is the evidence: it was written about
  # `.codex/hooks.json` while two siblings were being created two hundred lines above it.
  #
  # TWO DISJUNCTS, and the first is this run's own knowledge: after a successful write the file no
  # longer matches the PREVIOUS receipt's checksum, so `owned_by_installer` alone would decline the
  # row it was just asked to record.
  if [ -f "$CODEX_HOOKS_JSON" ] \
     && { [ "$HOOKS_JSON_OK" -eq 1 ] || owned_by_installer '.codex/hooks.json' ''; }; then
    printf '.codex/hooks.json\t%s\t%s\ttoolkit\n' "$(sha_of "$CODEX_HOOKS_JSON")" \
      "$(stat -c '%a' "$CODEX_HOOKS_JSON" 2>/dev/null || echo 644)" >> "$RECEIPT_TMP"
  fi

  # ── 8d.5 .codex/config.toml — the MCP server row ────────────────────────
  # The CONFIGURATION shape is measured — Codex's own importer writes exactly this row pointing at
  # the bridge — and whether the routes BEHAVE under Codex is not: Task 7 has not run. The entry
  # document marks that question open; this writes the configuration and claims nothing more.
  #
  # Same shape as .mcp.json above, including the refusal to rewrite a config.toml that is the
  # user's: a project .codex/config.toml can carry model settings, approval policy and sandbox
  # rules, none of which are ours to reformat.
  cat > "$CODEX_CFG_REF" <<'CODEXCFG'
[mcp_servers.UnityMCP]
url = "http://localhost:8080/mcp"
CODEXCFG
  if [ ! -f "$CODEX_CFG" ]; then
    # Status read — the same class member as .mcp.json, in the directory this arm has just created.
    if cat "$CODEX_CFG_REF" > "$CODEX_CFG"; then
      ok "Wrote .codex/config.toml (UnityMCP → http://localhost:8080/mcp)"
    else
      rm -f "$CODEX_CFG"
      warn ".codex/config.toml could not be written — the directory would not take it."
      note_not_done ".codex/config.toml — it could not be written, so a Codex session in this project reaches no Unity bridge. Check that .codex/ is writable and re-run install.sh --client codex."
    fi
  elif grep -qF -- 'mcp_servers.UnityMCP' "$CODEX_CFG" 2>/dev/null; then
    ok ".codex/config.toml already has a UnityMCP server — left alone."
  else
    warn ".codex/config.toml exists without a UnityMCP server — not rewriting it. Add:"
    warn ''
    warn '    [mcp_servers.UnityMCP]'
    warn '    url = "http://localhost:8080/mcp"'
    note_not_done ".codex/config.toml — yours has no UnityMCP server and was not rewritten, so a Codex session in this project reaches no Unity bridge. Add the [mcp_servers.UnityMCP] block printed above."
  fi
  if owned_by_installer '.codex/config.toml' "$CODEX_CFG_REF"; then
    printf '.codex/config.toml\t%s\t%s\ttoolkit\n' "$(sha_of "$CODEX_CFG")" \
      "$(stat -c '%a' "$CODEX_CFG" 2>/dev/null || echo 644)" >> "$RECEIPT_TMP"
  fi

  # ── 8d.6 hook trust — the one write that leaves the project ─────────────
  #
  # A registered hook does not run. Measured: with the project trusted and no hook trust, the hook
  # fired 0 times, the call went through, Codex printed no prompt and no warning, and `hooks/list`
  # at that same moment reported `enabled: true, trustStatus: untrusted, statusMessage: null`. That
  # is layer 3 of the six silent-failure layers this wave measured, and it sits above the hook body
  # (layer 4), which is why an untrusted hook never reaches the code that would have refused. This
  # comment read "a fifth silent-failure layer sitting above the other four" until 2026-08-17: the
  # ordinal was written mid-measurement, four layers were known then and six are known now, and the
  # canonical numbering is `findings.md` § *The six silent-failure layers, in one place*.
  #
  # Trust cannot ship in this repository. Putting `trusted_hash` inside the matcher group in
  # hooks.json is silently ignored — same hash, `warnings: []`, still untrusted — because the
  # app-server's own schema has no such field. A project cannot vouch for itself, which is the point
  # of the gate. So the LOCATION is the user's `$CODEX_HOME/config.toml` or nowhere.
  #
  # THE LOCATION IS SETTLED; THE MECHANISM IS A CHOICE, AND IT WAS NOT ENUMERATED BEFORE IT WAS MADE.
  # `config/value/write` and `config/batchWrite` are live app-server methods whose params carry
  # `filePath` (defaulting to the user's `config.toml`), `keyPath`, `value`, `mergeStrategy` and an
  # `expectedVersion` for optimistic concurrency. A structured write through Codex's own writer would
  # not have had a file mode to lose, which is the defect the `cat >` note below repairs by hand.
  #
  # IT IS STILL HAND-ROLLED, DELIBERATELY, AND HERE IS THE TRADE. Nothing in this wave has measured
  # how `keyPath` addresses a key that is itself a quoted absolute path containing `:`, `/` and `.`
  # — which is exactly the shape of every key here — nor what `mergeStrategy` does to a table that
  # already exists, nor whether a failed `expectedVersion` leaves the file partly written. Adopting
  # an unmeasured write path into a user's HOME on the strength of a schema read is the substitution
  # this wave exists to avoid; the hand-rolled path is measured end to end, backed up, reversible and
  # byte-idempotent. Measuring those three questions is the work that would justify the swap, and it
  # is recorded as the better mechanism once someone does it.
  #
  # THE SHAPES THE LINE-ORIENTED PASS WAS TESTED AGAINST are in tests/test-codex-surface.sh: an
  # indented table, CRLF line endings, a table immediately followed by another table, a comment
  # between tables, a foreign `hooks.state` table that must survive, a file with no trailing newline,
  # and an empty file. Its known limit is a multi-line basic string containing a line that begins
  # with `[` — a line-oriented pass reads that as a table header. No Codex config carries one, the
  # backup covers it, and it is named here rather than left to be discovered.
  #
  # AND IT CANNOT BE PRECOMPUTED. The hash covers the hook's DECLARATION — command string, timeout,
  # matcher, event — and the command string embeds absolute paths, so it is path-dependent by
  # construction. Deterministic and home-independent, but only knowable on the target machine. The
  # order is therefore fixed and not negotiable: write hooks.json, ask `hooks/list`, write trust.
  #
  # WHAT TRUST MEANS, SAID TO THE USER RATHER THAN BURIED. Measured by mutating one thing at a time:
  # editing the hook SCRIPT does not change the hash; changing the config's `timeout` does. So this
  # vouches for a command line, not for code. Anything that can later write the script file changes
  # what runs, with no re-review and no notification. That sentence is printed at the prompt.
  #
  # `--dangerously-bypass-hook-trust` appears nowhere here and must not: a toolkit that tells users
  # to switch hook trust off is worse than one that ships no hooks. Nothing in the measurement
  # needed it.
  CODEX_TRUST_GRANT=0
  if [ "$HOOKS_JSON_OK" -eq 1 ]; then
    if [ "$CODEX_TRUST" = yes ]; then
      CODEX_TRUST_GRANT=1
    elif [ "$CODEX_TRUST" = no ]; then
      info "--no-codex-trust — hook trust not granted; the hooks will register and not run."
    elif [ "$ASSUME_YES" -eq 1 ] || [ ! -t 0 ]; then
      # THE SAFE DEFAULT FOR A WRITE OUTSIDE THE PROJECT IS NOT TO MAKE IT. `--yes` means "take the
      # safe default at every prompt", and consent to modify a user's home directory is not
      # something a flag about prompts can supply.
      info "Non-interactive — hook trust NOT granted (it writes your home directory; pass --codex-trust to grant it)."
    else
      printf '\n  Codex will not run a hook until you trust it, and trust lives in your home\n'
      printf '  directory: %s/config.toml.\n' "$CODEX_HOME_DIR"
      printf '  Kinglet can back that file up and append one table per hook.\n'
      printf '  What you would be vouching for is the COMMAND LINE, not the code: editing a hook\n'
      printf '  script later does not re-open this question.\n'
      # SAID BEFORE THE ANSWER, NOT DISCOVERED AFTER IT. The hashes can only be read from a running
      # app server, and starting one makes Codex populate that home with its OWN state — caches,
      # sqlite stores, its built-in skills. None of it is Kinglet's and none of it is reversed by
      # uninstall.sh, so a user consenting to "one table per hook" would otherwise find a directory
      # they did not expect and no account of where it came from.
      printf '  Reading the hashes starts codex app-server briefly, and Codex writes its own\n'
      printf '  state into that directory when it starts. Kinglet reverses only its own tables.\n'
      read -rp "  Grant Codex hook trust for this project? [y/N]: " REPLY_TRUST
      case "$REPLY_TRUST" in [yY]*) CODEX_TRUST_GRANT=1 ;; esac
    fi
  fi

  if [ "$CODEX_TRUST_GRANT" -eq 1 ]; then
    TRUST_SKIP_WHY=""
    TRUST_CFG="$CODEX_HOME_DIR/config.toml"
    # "the only route measured", not "the only route there is". `hooks/list` is where this wave read
    # the hashes; the hash is deterministic and home-independent, so a reimplementation is
    # conceivable and simply has not been measured. The distinction matters because writing a
    # superlative over the routes that were TRIED as a superlative over the routes that EXIST is the
    # error this wave has now made four times.
    command -v codex >/dev/null 2>&1 || TRUST_SKIP_WHY="the codex CLI is not on PATH, and hooks/list is the only route measured for reading the hashes"
    if [ -z "$TRUST_SKIP_WHY" ] && ! command -v jq >/dev/null 2>&1; then
      TRUST_SKIP_WHY="jq is not on PATH"
    fi
    if [ -z "$TRUST_SKIP_WHY" ] && ! mkdir -p "$CODEX_HOME_DIR" 2>/dev/null; then
      TRUST_SKIP_WHY="$CODEX_HOME_DIR could not be created"
    fi
    if [ -z "$TRUST_SKIP_WHY" ] && [ ! -w "$CODEX_HOME_DIR" ]; then
      TRUST_SKIP_WHY="$CODEX_HOME_DIR is not writable"
    fi
    # THE DIRECTORY BEING WRITABLE SAYS NOTHING ABOUT THE FILE, and the test above is about the
    # directory. A `config.toml` at mode 444 sits perfectly happily inside a writable home, so it
    # passed every precondition and was then replaced — measured: 444 in, 600 out, trust granted, no
    # warning. Someone who made their Codex config read-only did that on purpose, and the answer to
    # a deliberate read-only file is to decline rather than to route around it.
    if [ -z "$TRUST_SKIP_WHY" ] && [ -e "$TRUST_CFG" ] && [ ! -w "$TRUST_CFG" ]; then
      TRUST_SKIP_WHY="$TRUST_CFG is not writable — it looks deliberately read-only, and this installer will not route around that"
    fi

    if [ -z "$TRUST_SKIP_WHY" ]; then
      info "Reading the hook hashes Codex computed (this starts codex app-server briefly)…"
      TRUST_OUT=$(mktemp)
      # STDIN IS HELD OPEN UNTIL THE REPLY LANDS, and that is not a stylistic choice: the app server
      # exits when its input closes, so a request written and immediately followed by EOF is a
      # request whose answer cannot arrive. Polling rather than a fixed sleep, so an ordinary run
      # costs a second or two instead of the ten a safe fixed sleep would need — with a ceiling, so
      # a Codex that never answers cannot hang an install.
      #
      # `grep -q` on a FILE ARGUMENT, never on a pipe: grep exits at the first match without
      # draining, and on a pipe that is the SIGPIPE-plus-pipefail death this repository's shell
      # conventions are mostly about. A file argument has no writer to signal.
      #
      # TWO QUESTIONS IN THE ONE SESSION, AND THE ORDER OF THE IDS IS DELIBERATE.
      #
      # `configRequirements/read` goes FIRST and `hooks/list` LAST, because the poll below waits for
      # the LAST id. An unknown method is answered with an error rather than a hang — that is how
      # this server's method list gets enumerated at all — so if a future Codex drops the
      # requirements route, id 2 errors, id 3 still answers, and the trust step is unaffected. The
      # other order would make an optional diagnostic able to stall the load-bearing request.
      {
        printf '%s\n' \
          '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"clientInfo":{"name":"kinglet-install","version":"1"}}}' \
          '{"jsonrpc":"2.0","method":"initialized"}' \
          '{"jsonrpc":"2.0","id":2,"method":"configRequirements/read","params":{}}' \
          "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"hooks/list\",\"params\":{\"cwds\":[\"$PROJECT_DIR\"]}}"
        TRUST_WAIT=0
        while [ "$TRUST_WAIT" -lt 300 ]; do
          grep -q '"id":3' "$TRUST_OUT" 2>/dev/null && break
          sleep 0.1
          TRUST_WAIT=$((TRUST_WAIT + 1))
        done
      } | CODEX_HOME="$CODEX_HOME_DIR" codex app-server > "$TRUST_OUT" 2>/dev/null || true

      # ── The managed-hooks switch, asked rather than assumed ─────────────
      #
      # WHAT IS MEASURED AND WHAT IS NOT, stated here because the branch below is half-exercised.
      # `configRequirements/read` is a LIVE route in 0.145.0 and answers `{"requirements": null}` —
      # verified twice, independently. Its response type carries `allowManagedHooksOnly`, and the
      # schema's own description names the source: "Null if no requirements are configured (e.g. no
      # requirements.toml/MDM entries)."
      #
      # NOBODY HAS MADE THE PAYLOAD NON-NULL. Two people tried; a `requirements.toml` in the home
      # under both spellings and under a `managed/` subdirectory all returned null. So the `true`
      # arm below has never been reached by a real policy — it is exercised by a stubbed response in
      # tests/test-codex-surface.sh instead, which is the difference between a branch that is tested
      # and a branch that is proven to fire in the field.
      #
      # The wording therefore claims detection of what Codex REPORTS, not of what an organisation
      # has SET. If those differ, this says nothing and the hooks quietly do not run — which is why
      # the sentence printed names its own uncertainty rather than reassuring.
      TRUST_MANAGED="$(jq -r 'select(.id==2)|.result.requirements.allowManagedHooksOnly // empty' \
        "$TRUST_OUT" 2>/dev/null | tr -d '[:space:]' || true)"
      if [ "$TRUST_MANAGED" = "true" ]; then
        warn "Codex reports allowManagedHooksOnly for this machine."
        warn "If that is in force, project-scoped hooks may not run AT ALL, and no amount of trust"
        warn "changes it — it is an organisation policy, not a Kinglet setting. Kinglet has never"
        warn "observed this switch set, so what follows may be granted into a layer that is inert."
        note_not_done "Codex reports allowManagedHooksOnly, which is an organisation policy Kinglet cannot change and has never observed set. If it is in force, .codex/hooks.json may not run at all whatever its trust says. Confirm with whoever manages your Codex configuration before relying on the hook layer."
      fi

      TRUST_PAIRS=$(mktemp)
      jq -r 'select(.id==3)|.result.data[]?|.hooks[]?|"\(.key)\t\(.currentHash)"' \
        "$TRUST_OUT" 2>/dev/null | sort -u > "$TRUST_PAIRS" || true
      TRUST_N=$(grep -c . "$TRUST_PAIRS" || true)

      if [ "$TRUST_N" -eq 0 ]; then
        # MEASURED, AND IT IS THE ANSWER A USER NEEDS RATHER THAN A GENERIC FAILURE. Against a
        # project Codex does not yet trust, `hooks/list` returns `hooks: [], warnings: [], errors:
        # []` — zero hooks and no diagnostic of any kind. So the hooks are not merely untrusted at
        # that point, they are not registered at all, and neither Codex nor this installer can tell
        # the user why unless it says so here.
        warn "Codex listed no hooks for this project, so there is nothing to grant trust to."
        warn "Measured: an untrusted project reports an EMPTY hook list with no warning and no error."
        warn "Run 'codex' once in this project and accept its trust prompt, then re-run:"
        warn "    ./install.sh --project-dir \"$PROJECT_DIR\" --client codex --codex-trust"
        note_not_done "Codex hook trust was NOT granted: 'hooks/list' returned no hooks for this project, which is what Codex reports for a project it has not been told to trust. The hooks are on disk and will not run. Run 'codex' once in the project, accept its trust prompt, then re-run install.sh with --client codex --codex-trust."
      else
        # ── COMPUTE, COMPARE, THEN BACK UP AND WRITE ──────────────────────
        #
        # THE ORDER USED TO BE BACK UP, THEN WRITE, AND THAT MADE THE BACKUP WORTHLESS. A backup
        # exists so the original can come back. Because the grant is idempotent, every re-grant
        # produced a copy of the POST-grant state — so backup 1 held the user's true original and
        # backups 2..N were byte-identical copies of a state the user already had. Keeping the
        # newest three then kept three copies of the same thing and evicted the only irreplaceable
        # one. Measured on a five-grant rig: no surviving backup held the original.
        #
        # BOTH HALVES OF THE FIX, because either alone leaves a hole:
        #
        #   1. NO CHANGE, NO BACKUP. The whole result is built in a temp file and compared with what
        #      is on disk. A re-grant that would write identical bytes writes nothing at all — no
        #      copy, no reap, not even an mtime — so the original is never pushed out in the common
        #      case, and the file the user sees is untouched rather than rewritten with its own
        #      content.
        #   2. THE OLDEST IS NEVER REAPED. When the result genuinely differs — a hook's timeout
        #      changed, so the hashes did — a backup is warranted and the set can still grow. The
        #      bound keeps the OLDEST (the pre-Kinglet original) plus the newest two, rather than
        #      the newest three, because "the state before any of this" is the one a recovery
        #      actually wants and it is the one that can never be reconstructed.
        TRUST_BACKUP="-"
        TRUST_WROTE=1
        TRUST_REAPED=0
        TRUST_UNCHANGED=0
        TRUST_PREEXISTED=1
        if [ ! -f "$TRUST_CFG" ]; then
          TRUST_PREEXISTED=0
          : > "$TRUST_CFG" || TRUST_WROTE=0
        fi

        if [ "$TRUST_WROTE" -eq 0 ]; then
          warn "Could not create $TRUST_CFG — hook trust not granted, and nothing was written."
          note_not_done "Codex hook trust was NOT granted: $TRUST_CFG could not be created."
        else
          # IDEMPOTENT BY DELETE-THEN-APPEND, not by append-if-absent. A re-install whose hook
          # config changed keeps the same KEYS and gets new HASHES, so appending would write a
          # second `[hooks.state."<key>"]` table with the same name — a duplicate table, which is a
          # TOML parse error, in the user's home config. Removing our previous block first makes two
          # identical runs produce a byte-identical file, which is what idempotent has to mean here.
          #
          # Only OUR tables are removed: those whose key `hooks/list` just reported for THIS
          # project, plus the marker line. A hook-trust table for another project is not ours.
          # DID THE USER'S FILE END IN A NEWLINE BEFORE KINGLET EVER TOUCHED IT?
          #
          # The append cannot avoid adding one — our marker would otherwise land on the end of their
          # last line — so the byte is not optional on install. What it costs is the exactness of the
          # REVERSAL: without this flag, `uninstall.sh` hands back a file one byte longer than the one
          # it was given, which is the same class of unannounced change as the file mode, and this
          # task's own guard measured it on a config whose last line carried no newline.
          #
          # STICKY, AND THAT IS THE WHOLE SUBTLETY. Asking the question on every grant answers it
          # about the file AS THIS TOOLKIT LAST LEFT IT: after grant 1 the last line is our own
          # appended table, which certainly ends in a newline, so grant 2 recorded `yes` and undid
          # grant 1's correct `no`. The reversal then reintroduced the byte, and the failure appeared
          # only on the second install — the shape this installer has already paid for twice with
          # `user-modified`.
          #
          # THREE WITNESSES, IN ORDER, BECAUSE ONE WAS A SINGLE POINT OF FAILURE. The record alone
          # meant deleting `.claude/state/codex-trust.tsv` between grants re-opened the exact bug
          # this flag fixes — grant 2 re-asks against the file as the toolkit left it and records
          # `yes`. So:
          #
          #   1. the reversal record, which is authoritative and free;
          #   2. failing that, the OLDEST surviving `.kinglet-backup.*` — a copy of the file from
          #      before Kinglet first touched it, which the reaping rule above now guarantees is
          #      never evicted. This is why these two findings are one change: the backup policy is
          #      what makes the second witness durable enough to be worth consulting;
          #   3. failing both, the config itself — correct only when Kinglet has never written it,
          #      which is exactly the case where our marker is absent.
          #
          # AND WHEN ALL THREE FAIL, SAY SO. Marker present, no record, no backup: the original
          # state is genuinely unrecoverable. The conservative answer is `yes` (leave the newline),
          # whose cost is one byte on the reversal — but a user who deleted both witnesses is owed
          # the sentence rather than a silent guess.
          TRUST_HAD_NL=""
          TRUST_NL_SRC=""
          if [ -f "$PROJECT_DIR/$CODEX_TRUST_REL" ]; then
            TRUST_HAD_NL=$(awk '/^# original-trailing-newline: /{sub(/^# original-trailing-newline: /, ""); print; exit}' \
              "$PROJECT_DIR/$CODEX_TRUST_REL")
            [ -z "$TRUST_HAD_NL" ] || TRUST_NL_SRC="the reversal record"
          fi
          if [ -z "$TRUST_HAD_NL" ]; then
            TRUST_OLDEST_BK=""
            for tb in "$TRUST_CFG".kinglet-backup.*; do
              if [ -f "$tb" ]; then TRUST_OLDEST_BK="$tb"; break; fi
            done
            if [ -n "$TRUST_OLDEST_BK" ]; then
              TRUST_HAD_NL=yes
              if [ -s "$TRUST_OLDEST_BK" ] && [ -n "$(tail -c1 "$TRUST_OLDEST_BK")" ]; then TRUST_HAD_NL=no; fi
              TRUST_NL_SRC="the oldest backup ($(basename "$TRUST_OLDEST_BK"))"
            fi
          fi
          if [ -z "$TRUST_HAD_NL" ]; then
            TRUST_HAD_NL=yes
            if [ -s "$TRUST_CFG" ] && [ -n "$(tail -c1 "$TRUST_CFG")" ]; then TRUST_HAD_NL=no; fi
            TRUST_NL_SRC="the config itself"
            if grep -qF -- 'kinglet:codex-trust' "$TRUST_CFG" 2>/dev/null; then
              warn "$TRUST_CFG already carries a Kinglet grant, but neither its reversal record nor a"
              warn "backup survives — so whether it originally ended in a newline cannot be recovered."
              warn "The reversal may leave one extra byte. Neither file should be deleted by hand."
              TRUST_NL_SRC="a guess — both witnesses are gone"
            fi
          fi
          TRUST_KEYS=$(mktemp)
          cut -f1 "$TRUST_PAIRS" > "$TRUST_KEYS"
          TRUST_MARK="# kinglet:codex-trust — hook trust for $PROJECT_DIR (remove with uninstall.sh)"
          TRUST_NEW=$(mktemp)
          TRUST_CLEANED=1
          awk -v keyfile="$TRUST_KEYS" -v mark="$TRUST_MARK" '
            BEGIN {
              while ((getline k < keyfile) > 0) { drop["[hooks.state.\"" k "\"]"] = 1 }
              inblock = 0
            }
            {
              line = $0
              sub(/^[[:space:]]+/, "", line)
              sub(/[[:space:]]+$/, "", line)
              if (line == mark) { next }
              if (line in drop) { inblock = 1; next }
              if (inblock && line ~ /^\[/) { inblock = 0 }
              if (inblock) { next }
              print
            }
          ' "$TRUST_CFG" > "$TRUST_NEW" || TRUST_CLEANED=0

          # THE APPEND IS GATED ON THE CLEAN HAVING HAPPENED, and that is not defensive
          # decoration. Appending to a file the removal pass failed on writes a SECOND
          # `[hooks.state."<key>"]` table with a name already in the file — a duplicate table, which
          # is a TOML parse error in the user's home config, produced by the step meant to repair it.
          if [ "$TRUST_CLEANED" -eq 0 ]; then
            warn "Could not rewrite $TRUST_CFG — hook trust NOT granted, and the file is as it was."
            note_not_done "Codex hook trust was NOT granted: $TRUST_CFG could not be rewritten, so nothing was appended to it. The hooks are registered and will not run."
            rm -f "$TRUST_NEW"
          else

          # The whole result, assembled where nobody can see it. Nothing has touched the user's file
          # at this point, which is what lets the comparison below decide whether to touch it at all.
          TRUST_CAND=$(mktemp)
          {
            cat "$TRUST_NEW"
            printf '%s\n' "$TRUST_MARK"
            while IFS=$'\t' read -r tk th; do
              [ -n "$tk" ] || continue
              printf '[hooks.state."%s"]\nenabled = true\ntrusted_hash = "%s"\n' "$tk" "$th"
            done < "$TRUST_PAIRS"
          } > "$TRUST_CAND"
          rm -f "$TRUST_NEW"

          if cmp -s "$TRUST_CAND" "$TRUST_CFG"; then
            # ALREADY EXACTLY RIGHT. The common case on every re-install: same hooks, same config,
            # same hashes. Writing identical bytes would be indistinguishable from writing nothing
            # except for the backup it drags in — and that backup is the one that used to push the
            # user's original out of the bound.
            TRUST_UNCHANGED=1
          else
            # A BACKUP ONLY WHERE THERE IS SOMETHING TO LOSE. `TRUST_PREEXISTED` is 0 when this run
            # created the file, and an empty file this run made needs no copy.
            if [ "$TRUST_PREEXISTED" -eq 1 ]; then
              TRUST_BACKUP="$TRUST_CFG.kinglet-backup.$(date -u +%Y%m%d%H%M%S)"
              cp "$TRUST_CFG" "$TRUST_BACKUP" || TRUST_WROTE=0
            fi
            if [ "$TRUST_WROTE" -eq 0 ]; then
              warn "Could not back up $TRUST_CFG — hook trust not granted, and nothing was written."
              note_not_done "Codex hook trust was NOT granted: $TRUST_CFG could not be backed up, and this installer does not edit a home file it cannot first copy."
            else
              # `cat >` RATHER THAN `mv`, AND THE REASON IS THE FILE'S MODE. `mv` from `mktemp`
              # replaces the inode and carries 0600 with it, so a home config at 644 came out 600 and
              # one at 444 came out 600 — a silent change to a property of a file this toolkit did
              # not create, in the one place it is least entitled to make one. Measured, three ways,
              # in both directions of the round trip; a reviewer then held it at 664, 640 and 755.
              # The same trap is documented twice elsewhere in this file for project files, with
              # `chmod 644` as the fix; here there is no correct constant to chmod TO, because the
              # right mode is whatever the user already chose.
              #
              # Rewriting the existing inode keeps mode, ownership and any ACL by construction, on
              # every platform, with no `stat` and therefore no GNU/BSD split. What it gives up is
              # atomicity: a crash between truncate and write leaves a short file. The backup taken
              # immediately above is the mitigation, and the alternative trades a rare, loud,
              # recoverable failure for a silent certain one.
              cat "$TRUST_CAND" > "$TRUST_CFG" || TRUST_WROTE=0

              # OLDEST PLUS THE NEWEST TWO. Sorted ascending, so record 1 is the pre-Kinglet
              # original: it is kept unconditionally, and the eviction window is everything between
              # it and the last two. `NR <= total - 2` with `NR != 1` is that window; at three or
              # fewer it selects nothing, which is why no separate guard is needed for a small set.
              TRUST_REAP=$(mktemp)
              for tb in "$TRUST_CFG".kinglet-backup.*; do
                if [ -f "$tb" ]; then printf '%s\n' "$tb" >> "$TRUST_REAP"; fi
              done
              TRUST_REAP_N=$(grep -c . "$TRUST_REAP" || true)
              while IFS= read -r tb; do
                [ -n "$tb" ] || continue
                rm -f "$tb" && TRUST_REAPED=$((TRUST_REAPED + 1))
              done <<< "$(sort "$TRUST_REAP" 2>/dev/null | awk -v total="$TRUST_REAP_N" 'NR != 1 && NR <= total - 2' || true)"
              rm -f "$TRUST_REAP"
            fi
          fi
          rm -f "$TRUST_CAND"

          # THE RECEIPT FOR A FILE THAT IS NOT OURS TO DELETE. Every other row in the receipt says
          # "this path is ours to remove"; this one cannot, because the file is the user's and only
          # the tables are ours. So the reversal is recorded as data — the config path, the backup,
          # and the exact keys — in a file that IS ours, carries its own ordinary receipt row, and
          # is what uninstall.sh reads to undo precisely this and nothing else.
          mkdir -p "$CLAUDE_DIR/state"
          {
            printf '# kinglet codex hook-trust record\n'
            printf '# Written by install.sh --client codex --codex-trust. uninstall.sh removes exactly\n'
            printf '# the [hooks.state."<key>"] tables listed below from the config named here.\n'
            printf '# DO NOT DELETE THIS FILE BY HAND. It is the only cheap record of what the home\n'
            printf '# config looked like before Kinglet touched it. Delete it and a later grant\n'
            printf '# falls back to the oldest .kinglet-backup.* copy; delete both and the reversal\n'
            printf '# can leave one byte behind. uninstall.sh removes it for you.\n'
            printf '# config: %s\n' "$TRUST_CFG"
            printf '# backup: %s\n' "$TRUST_BACKUP"
            printf '# granted-at: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
            printf '# marker: %s\n' "$TRUST_MARK"
            printf '# original-trailing-newline: %s\n' "$TRUST_HAD_NL"
            printf '# trailing-newline-source: %s\n' "$TRUST_NL_SRC"
            printf 'key\thash\n'
            cat "$TRUST_PAIRS"
          } > "$PROJECT_DIR/$CODEX_TRUST_REL"
          printf '%s\t%s\t%s\ttoolkit\n' "$CODEX_TRUST_REL" \
            "$(sha_of "$PROJECT_DIR/$CODEX_TRUST_REL")" \
            "$(stat -c '%a' "$PROJECT_DIR/$CODEX_TRUST_REL" 2>/dev/null || echo 644)" >> "$RECEIPT_TMP"

          # THE TWO OUTCOMES ARE DIFFERENT SENTENCES. "Granted" on a run that wrote nothing is a
          # small lie about a file outside the project, and it is exactly the run on which a user
          # would want to know their home was left alone.
          if [ "$TRUST_UNCHANGED" -eq 1 ]; then
            ok "Codex hook trust already granted for $TRUST_N hook(s) — $TRUST_CFG left untouched"
          else
            ok "Granted Codex hook trust for $TRUST_N hook(s) in $TRUST_CFG"
            [ "$TRUST_BACKUP" = "-" ] || ok "Backup: $TRUST_BACKUP"
            [ "$TRUST_REAPED" -eq 0 ] || info "Reaped $TRUST_REAPED intermediate backup(s); the original and the newest two are kept."
          fi
          warn "Hook trust vouches for a COMMAND LINE, not for code: anything that can write"
          warn "$CLAUDE_DIR/hooks/*.sh from now on changes what runs, with no re-review."
          fi
          rm -f "$TRUST_KEYS"
        fi
      fi
      rm -f "$TRUST_OUT" "$TRUST_PAIRS"
    else
      warn "Codex hook trust not granted: $TRUST_SKIP_WHY."
      note_not_done "Codex hook trust was NOT granted — $TRUST_SKIP_WHY. The hooks are registered in .codex/hooks.json and will NOT run until trust is granted. Fix that and re-run with --client codex --codex-trust."
    fi
  elif [ "$HOOKS_JSON_OK" -eq 1 ]; then
    # THE HONEST HALF-STATE, NAMED. A hook layer on disk that nothing has vouched for enforces
    # nothing, and `## Success criterion 1` says a user cannot tell from inside the session. That
    # last clause is scoped rather than absolute, and README.md § Hook trust now says where the line
    # falls: THIS state — registered, untrusted — is the one Codex WILL report, as
    # `trustStatus: "untrusted"` on an entry `hooks/list` still returns. The state nothing can see
    # is the project being untrusted, where the list comes back empty and there is no entry to carry
    # a status at all. Nothing in the shipped toolkit asks after install time either way, which is
    # why this note exists.
    note_not_done "Codex hook trust was not granted, so the $([ -f "$CODEX_HOOKS_JSON" ] && grep -c '"type": "command"' "$CODEX_HOOKS_JSON" 2>/dev/null || echo 0) registered hook(s) in .codex/hooks.json will NOT run: Codex ignores an untrusted hook silently. Grant it by running 'codex' once in this project and accepting its hook review, or re-run install.sh with --client codex --codex-trust."
  fi

  # `allowManagedHooksOnly` is an organisation policy: if it is in force, project-scoped hooks may
  # not run at all regardless of trust, and no amount of `hooks.state` would change that.
  #
  # THIS COMMENT READ "the one failure this installer cannot detect or repair" AND THE FIRST HALF WAS
  # WRONG. `configRequirements/read` is a live route in 0.145.0 that answers, and its response type
  # carries the field — so the installer had simply never asked, in a session it was already holding
  # open. It asks now, above. That was the fourth time in this wave a superlative over the routes
  # somebody tried got written as a superlative over the routes that exist, and the method that
  # refutes it every time is the same one: enumerate the schema bundle for the capability noun
  # before accepting a "there is no…" sentence.
  #
  # WHAT IS STILL TRUE, NARROWED TO WHAT IS PROVEN. Kinglet cannot REPAIR it — it is not Kinglet's
  # policy to change. And detection is proven only on the null side: two people have failed to make
  # `requirements` non-null, so nothing here demonstrates that a policy an organisation has actually
  # SET surfaces through that field. The correct sentence is "cannot repair, and does not yet detect
  # a set policy" — not "cannot detect", and not "detects".
else
  # ── Step 8e: a Codex layer this run did not write, and still owns ────────────
  #
  # THE DEFECT THIS CLOSES, MEASURED ON A FIXTURE 2026-08-16 (figures pinned to that tree: one row
  # per skill, one per command, plus three). `install.sh --client codex` writes its receipt rows
  # outside `.claude/` — the skill symlinks, the converted command skills, `AGENTS.md`,
  # `.codex/hooks.json`, `.codex/config.toml` — and the receipt is rebuilt from scratch on every run
  # with every one of those appends INSIDE the `--client codex` branch. So installing
  # `--client claude` over that project took the rows **28 -> 0** while leaving all 28 paths on disk.
  # The orphan prune in Step 3 cannot reach them either — it filters the previous receipt to
  # `^\.claude/` — so nothing removed the files and nothing owned them. `uninstall.sh` is
  # receipt-driven by design ("Refusing to guess which files are ours"), so the result was a project
  # the uninstaller left permanently dirty while every signal read healthy: `PASS Install intact:
  # 71 file(s) verified against the receipt`, `8 passed · 1 warning(s) · 0 failure(s)`, and an
  # uninstall that removed 71 of 99 and reported success with 28 files still there.
  #
  # THE ANSWER IS TO KEEP BOTH LAYERS AND KEEP BOTH SETS OF ROWS, and the alternative was weighed
  # rather than skipped. Removing the Codex layer on a Claude install is defensible in the abstract
  # and wrong here for one concrete reason: `claude` is the DEFAULT client, so every ordinary upgrade
  # — `./install.sh --project-dir X`, no `--client` at all — would silently delete a layer the user
  # asked for once, including the `.codex/hooks.json` whose per-hook trust tables live in their HOME
  # and whose only removal route is the receipt row this run would have just thrown away. It also
  # inverts the promise the other arm makes: `--client codex` never removes anything Claude Code
  # reads, and the mirror of that has to hold or the pair is a trap.
  #
  # THE ROWS ARE CARRIED VERBATIM, AND ONLY WHEN THE PATH STILL EXISTS. Verbatim, because a row means
  # "the toolkit wrote this file with this checksum": re-deriving the sha would newly claim ownership
  # of a file the user edited after the Codex install, and `uninstall.sh` would then delete it as
  # unchanged — the exact data loss its two-test classifier exists to prevent. That is measured, not
  # argued: with the two carried rows' shas re-derived by hand, `uninstall.sh` reports
  # `remove 99 file(s) — unchanged since install` and DELETES both edited files.
  # `-e || -L` and not `-f`, since the skill rows are symlinks to directories and `-f` is false for
  # every one of them (that spelling is what made `studio-doctor.sh` fail every correct Codex
  # install).
  #
  # A ROW WHOSE PATH IS GONE IS DROPPED — AND THE DROP IS SAID OUT LOUD, WHICH IS THE HALF THAT WAS
  # MISSING. Dropping is right: a row for a path that is not there is a ghost, and keeping it would
  # give a user who deliberately removed the Codex layer a permanently failing doctor with **no
  # targeted way to clear it** — a false-alarm generator, which this repository's own ledger rates as
  # the most expensive kind of red. *Targeted* is the load-bearing word and it replaced a categorical
  # that measurement refuted: `uninstall.sh --yes` followed by `install.sh --yes` does clear a ghost
  # row (0 Codex rows, `8 passed · 1 warning(s) · 0 failure(s)`), using only the two shipped commands
  # and keeping user-modified files by default. What does not exist is a per-layer route —
  # `uninstall.sh` takes `--project-dir/--yes/--purge/--keep-local/--no-backup` and nothing narrower —
  # so the only cure would be tearing the whole toolkit down and putting it back to silence a warning
  # about files the user deleted on purpose. That is still the wrong trade; it is a smaller claim than
  # the one this comment used to make. But SILENT dropping is worse than either. Measured 2026-08-16:
  # `studio-doctor.sh` correctly reports `FAIL 2 receipted file(s) missing — re-run install.sh`
  # (rc 1); following that remedy literally, with the DEFAULT client, dropped both rows and the next
  # doctor run read `8 passed · 1 warning(s) · 0 failure(s)` with both files still gone. The branch's
  # original Critical was a remedy that REPRODUCED the bad state; that one at least kept complaining.
  # So: count the drops, name them, and route a `note_not_done` — which prints immediately above
  # `Next steps:`, at the moment the user is reading. `studio-doctor.sh`'s remedy line now names
  # `--client codex` for these paths, so the two halves agree.
  #
  # `$RECEIPT` still holds the PREVIOUS run's receipt at this point — Step 9 is what replaces it —
  # which is the same fact four `owned_by_installer` call sites depend on.
  CODEX_CARRIED=0
  CODEX_DROPPED=0
  CODEX_DROPPED_LIST=""
  if [ "$MODE" = ours ] && [ -f "$RECEIPT" ]; then
    while IFS=$'\t' read -r cx_rel cx_sha cx_mode cx_origin; do
      case "$cx_rel" in ''|\#*|path) continue ;; esac
      codex_layer_path "$cx_rel" || continue
      if [ ! -e "$PROJECT_DIR/$cx_rel" ] && [ ! -L "$PROJECT_DIR/$cx_rel" ]; then
        CODEX_DROPPED=$((CODEX_DROPPED + 1))
        CODEX_DROPPED_LIST="${CODEX_DROPPED_LIST}${cx_rel}"$'\n'
        continue
      fi
      printf '%s\t%s\t%s\t%s\n' "$cx_rel" "$cx_sha" "$cx_mode" "$cx_origin" >> "$RECEIPT_TMP"
      CODEX_CARRIED=$((CODEX_CARRIED + 1))
    done < "$RECEIPT"
  fi
  if [ "$CODEX_CARRIED" -gt 0 ]; then
    info "Codex layer: $CODEX_CARRIED receipted path(s) kept — this run installed Claude Code only."
    info "Nothing Codex reads was removed. Re-run with --client codex to regenerate that layer."
  fi
  if [ "$CODEX_DROPPED" -gt 0 ]; then
    warn "$CODEX_DROPPED Codex-layer path(s) in the previous receipt are GONE from disk:"
    while IFS= read -r cx_d; do
      if [ -n "$cx_d" ]; then printf '       %s\n' "$cx_d"; fi
    done <<< "$CODEX_DROPPED_LIST"
    warn "Their receipt rows were dropped — this run installed Claude Code only and did not"
    warn "restore them. Re-run with --client codex to get that layer back."
    # THE ENFORCEMENT CLAUSE IS ADDED ONLY WHEN IT IS TRUE OF THIS RUN. It used to be an
    # unconditional "If .codex/hooks.json is among them…", which is a true sentence and was still a
    # defect: `tests/test-install-upgrade-client.sh` arm 4 asserted "the run names the path it
    # dropped" by grepping the whole run output for that literal, and the literal was present
    # whatever had actually been dropped. The assertion could not fail — the same hollow shape the
    # round before had just repaired elsewhere. Making the clause conditional removes the constant
    # AND makes the message per-run accurate; the arm now reads the `GONE from disk:` block instead.
    CODEX_DROP_NOTE="$CODEX_DROPPED Codex-layer path(s) listed above were missing from disk and their receipt rows were dropped, so nothing owns or reports them any more. This run was --client claude and does not write that layer."
    if grep -qxF -- '.codex/hooks.json' <<< "$CODEX_DROPPED_LIST"; then
      CODEX_DROP_NOTE="$CODEX_DROP_NOTE The hook config is one of them, so this project is advisory rather than enforcing under Codex."
    fi
    note_not_done "$CODEX_DROP_NOTE Re-run: ./install.sh --project-dir \"$PROJECT_DIR\" --client codex"
  fi
fi

# ── Step 9: Write the receipt ────────────────────────────────────────────────
# The body moved to write_receipt beside the trap that arms it (Step 5). Two copies of this heredoc
# — one for the ordinary path, one for the interrupted one — would be two definitions of the receipt
# format, and the difference between them would only ever show up in a project that already had the
# worse problem. RECEIPT_WRITTEN is set inside the function, so the trap knows there is nothing left
# to do.
write_receipt || die "Could not write $RECEIPT_REL — the payload is installed and unremovable; remove .claude/ by hand."
RECEIPT_ROWS=$(grep -vc '^#' "$RECEIPT" || true)
ok "Receipt written: $RECEIPT_REL ($((RECEIPT_ROWS - 1)) files)"

# ── Summary ──────────────────────────────────────────────────────────────────
# Counted, never hardcoded. Upstream's summary claimed 22 hooks / 22 commands / 41 skills while
# shipping 25 / 27 / 42, because the numbers were typed into an echo.
count_in() { find "$CLAUDE_DIR/$1" -name "$2" 2>/dev/null | wc -l | tr -d ' '; }
# Hooks are counted from settings.json, not from *.sh on disk: hooks/ also holds _lib.sh, a sourced
# library that is not itself a hook, so the file count and the hook count are never the same number.
# That still holds below — the sweep is settings.json's registrations, and _lib.sh is never one of
# them — but a registration is now only counted once the file it names exists.
#
# THE NUMBER USED TO BE A COUNT OF REGISTRATIONS AND NOTHING ELSE, and after an upgrade across a
# payload that shrank it printed the pre-cut figure over a tree that no longer held those files:
# `Hooks 27` with 12 on disk, measured. It is the user's file, correctly kept, so the stale entries
# are still there and no re-run clears them.
#
# BOTH NUMBERS, NOT THE SMALLER ONE. Reporting only what will fire is the honest half of the answer
# and it is also the quiet one: `Hooks 12` agrees with a healthy tree, so the summary — the last
# thing printed, and on a long upgrade the only thing read — would look identical to a project with
# nothing wrong while fifteen entries in the user's file still named deleted scripts. That is the
# same defect as the one being repaired, one digit to the left. The parenthetical appears only when
# something is dead, so an ordinary install still prints a bare number and the warning block above
# is what the reader is being pointed back at.
count_hooks() {
  local registered
  local live
  local dead
  local ch_h
  registered=$(grep -oE '\.claude/hooks/[a-z_-]+\.sh' "$CLAUDE_DIR/settings.json" 2>/dev/null | sort -u || true)
  live=0
  dead=0
  # A settings.json that is missing or registers nothing yields one empty line here, which the
  # `continue` drops — so both counters stay 0 and the bare `0` the old one-liner printed is
  # preserved. `<<<` and not a pipe: the loop drains either way, but a here-string keeps the
  # counters out of a subshell, where they would be incremented and then thrown away.
  while IFS= read -r ch_h; do
    [ -n "$ch_h" ] || continue
    if [ -f "$PROJECT_DIR/$ch_h" ]; then live=$((live + 1)); else dead=$((dead + 1)); fi
  done <<< "$registered"
  if [ "$dead" -gt 0 ]; then
    printf '%s (%s registered, %s dead)\n' "$live" "$((live + dead))" "$dead"
  else
    printf '%s\n' "$live"
  fi
}
# THE CODEX BLOCK BELOW EXISTS BECAUSE THE FIVE NUMBERS ABOVE ARE TRUE AND MISLEADING AT ONCE.
# They count what landed under `.claude/`, which is correct for both clients — `--client codex` adds
# a layer and removes nothing Claude Code reads. But printed alone to a Codex user they say
# `Agents 8` about agents this toolkit deliberately EXCLUDES from the Codex layer, and `Commands 9`
# about a surface `codex-cli 0.145.0` does not have at all. The branch's headline finding and the
# installer's last line contradicted each other on one screen, and the last line is what a user
# screenshots.
#
# COUNTED FROM DISK AT THIS POINT, like every other figure here, and NOT from the SKILLS_LINKED /
# CMDSKILL_W accumulators above: those are what THIS RUN wrote, and on a re-install that keeps a
# user's edited file the accumulator and the tree disagree.
#
# THE TWO ARMS DO NOT PARTITION THE ROOT, and this comment said they did until 2026-09-08. `-type l`
# and `-type d` are exhaustive only over a directory containing nothing else and nothing foreign:
#   * a symlink someone else put here is `-type l` and was NOT bridged by us;
#   * a plain directory someone else put here is `-type d` and is NOT a converted command — the run
#     may have declined it three lines earlier and still counted it as one;
#   * a plain FILE here (a stray README) is in the unqualified total and in neither arm, so the
#     parenthesised halves stop summing.
# Measured: with a foreign `.agents/skills/physics/` present, the summary read
# `Skills 25 (15 bridged, 10 commands converted)` four lines under `Converted 9 command(s)`.
#
# So `bridged` now applies the SAME ownership test the link loop and the prune use — the target must
# be exactly `../../.claude/skills/<the entry's own name>` — and anything the two arms cannot claim
# is reported as `not ours` rather than absorbed into one of them. A number that cannot account for
# itself is worse than a number that admits a remainder, and this is the line a user screenshots.
# NO PARAMETERS, since 2026-09-08. This took a `find` predicate so the caller could ask for
# `-type d`; the converted-command count now comes from the receipt instead, and nothing has passed
# an argument since. `"$@"` on an always-empty parameter list is a seam that reads as configurable
# and is not, which is what SC2120 exists to say.
count_agents_root() {
  # `|| true` ON THE WRITER, and it is load-bearing since these became assignments. `find` returns 1
  # for a path it cannot read — a sealed project root is exactly that — `2>/dev/null` hides the
  # message and not the status, and `pipefail` promotes it to the pipeline's. Inside a `printf`
  # argument that was harmless because `printf` still succeeded; in `X=$(count_agents_root)` under
  # `set -e` it ends the run at the summary, with everything already written. Caught by
  # tests/test-install-not-done.sh B.7c, which builds that sealed root on purpose.
  { find "$PROJECT_DIR/.agents/skills" -mindepth 1 -maxdepth 1 2>/dev/null || true; } \
    | wc -l | tr -d ' '
}

# Links that are OURS: a symlink whose target is exactly the skill of the same name.
count_agents_bridged() {
  local n=0 entry
  for entry in "$PROJECT_DIR/.agents/skills"/*; do
    [ -L "$entry" ] || continue
    [ "$(readlink "$entry")" = "../../.claude/skills/$(basename "$entry")" ] && n=$((n + 1))
  done
  printf '%s' "$n"
}

# Converted command skills that are OURS, read from the receipt rather than guessed from the mode
# bits. `-type d` cannot tell a directory this run wrote from one the user put there — and the run
# may have declined that very directory three lines earlier while still counting it as a command it
# converted. The receipt is written at Step 9, above this block, so it is current and it is the only
# thing on disk that records ownership.
count_agents_converted() {
  [ -f "$RECEIPT" ] || { printf '0'; return; }
  awk -F'\t' '$1 ~ /^\.agents\/skills\/[^/]+\// {
    split($1, seg, "/"); seen[seg[3]] = 1
  } END { n = 0; for (k in seen) n++; printf "%d", n }' < "$RECEIPT" 2>/dev/null || printf '0'
}

# Registered hook entries in a Codex hook config, counted WITHOUT assuming jq's spacing.
#
# This was `grep -c '"type": "command"' FILE 2>/dev/null || echo 0`, which had two defects in one
# expression. `grep -c` prints `0` AND exits 1 when it matches nothing, so the `|| echo 0` fired as
# well and the substitution expanded to TWO lines — `printf '    Hooks     %s  %s\n'` then broke
# across two lines with the trust sentence stranded on the second. Measured, not theorised:
#     Hooks     0
#   0  in .codex/hooks.json — NOT trusted yet, so they will not run
# And the pattern matched jq's exact pretty-printed spacing, so a `.codex/hooks.json` the installer
# correctly KEPT because it is the user's — written by something else, with its own formatting —
# counted 0 whether it registered no hooks or ten. Those are the two cases this line exists to tell
# apart. awk, so there is no early-exiting reader in a pipeline and no exit status to rescue.
count_codex_hooks() {
  local f="$PROJECT_DIR/.codex/hooks.json"
  [ -f "$f" ] || { printf '0'; return; }
  awk '{ gsub(/[ \t]/, ""); total += gsub(/"type":"command"/, "") } END { printf "%d", total + 0 }'     "$f" 2>/dev/null || printf '0'
}
printf '\n%s\n' "${BOLD}${GREEN}Installation complete.${NC}"
if [ "$CLIENT" = codex ]; then
  printf '  %s.claude/ — what Claude Code reads%s\n' "$CYAN" "$NC"
  printf '    Agents    %s\n'   "$(count_in agents '*.md')"
  printf '    Commands  %s\n'   "$(count_in commands '*.md')"
  printf '    Skills    %s\n'   "$(count_in skills 'SKILL.md')"
  printf '    Hooks     %s\n'   "$(count_hooks)"
  printf '    Rules     %s\n'   "$(count_in rules '*.md')"
  printf '  %sCodex CLI — what crosses%s\n' "$CYAN" "$NC"
  AGENTS_TOTAL=$(count_agents_root); AGENTS_BRIDGED=$(count_agents_bridged)
  AGENTS_CONVERTED=$(count_agents_converted); AGENTS_OTHER=$((AGENTS_TOTAL - AGENTS_BRIDGED - AGENTS_CONVERTED))
  printf '    Skills    %s  (%s bridged from .claude/skills/, %s commands converted%s)\n' \
    "$AGENTS_TOTAL" "$AGENTS_BRIDGED" "$AGENTS_CONVERTED" \
    "$([ "$AGENTS_OTHER" -ne 0 ] && printf ', %s not ours' "$AGENTS_OTHER" || true)"
  printf '    Hooks     %s  %s\n' \
    "$(count_codex_hooks)" \
    "$(if [ "${TRUST_N:-0}" -gt 0 ] && [ "${CODEX_TRUST_GRANT:-0}" -eq 1 ]; then printf 'in .codex/hooks.json, trusted'; else printf 'in .codex/hooks.json — NOT trusted yet, so they will not run'; fi)"
  printf '    Commands  0  no command surface exists in Codex; the nine crossed as skills above\n'
  printf '    Agents    0  excluded on purpose — Codex has no per-agent tool allowlist\n'
  printf '    Rules     %s  reachable, but nothing loads them for you — AGENTS.md carries the pointer\n' "$(count_in rules '*.md')"
else
  printf '  %sAgents%s    %s\n'   "$CYAN" "$NC" "$(count_in agents '*.md')"
  printf '  %sCommands%s  %s\n'   "$CYAN" "$NC" "$(count_in commands '*.md')"
  printf '  %sSkills%s    %s\n'   "$CYAN" "$NC" "$(count_in skills 'SKILL.md')"
  printf '  %sHooks%s     %s\n'   "$CYAN" "$NC" "$(count_hooks)"
  printf '  %sRules%s     %s\n'   "$CYAN" "$NC" "$(count_in rules '*.md')"
fi
# The CLAUDE.md step names whichever file this run actually wrote to — not a fixed string. See
# defect 9: telling the user to edit CLAUDE.md in the run where CLAUDE.md.generated was written
# instead sends them to markers that live in a file the message never mentioned.
case "$CLAUDE_MD_BRANCH" in
  new)
    CLAUDE_MD_STEP='Fill in the FILL: markers in CLAUDE.md — genre, pillars, vision, scope.'
    ;;
  separate)
    CLAUDE_MD_STEP='Fill in the FILL: markers in CLAUDE.md.generated, then merge what you want into your own CLAUDE.md.'
    ;;
  refreshed)
    CLAUDE_MD_STEP='CLAUDE.md already had its generated section refreshed — your own prose was left untouched.'
    ;;
  # NOT `*)`. That arm says "generation was skipped", and this is a file that exists, carries the
  # markers, and kept the user's prose — only the generated block is a run behind. Sending that reader
  # to a warning about generation would describe someone else's project.
  refresh-failed)
    CLAUDE_MD_STEP='CLAUDE.md was not refreshed this run — its generated block still carries an earlier run'"'"'s project facts, and your own prose was not touched. See the warning above.'
    ;;
  # NOT `kept-yours`, which says the file was kept because it is yours. This one is ours and could not
  # be written; the two need different sentences because they need different actions.
  generated-not-written)
    CLAUDE_MD_STEP='Nothing was written beside your CLAUDE.md this run — see the warning above. Your own CLAUDE.md was not touched.'
    ;;
  # The decline. Sending the user to "the FILL: markers in CLAUDE.md.generated" here would point at a
  # file this run deliberately did not write, whose contents are the user's own and contain no
  # markers — defect 9's failure with the files swapped.
  kept-yours)
    CLAUDE_MD_STEP='Your own CLAUDE.md.generated was kept — no generated file was produced. Rename or delete it and re-run to get one.'
    ;;
  # The other decline, and the reason it does not fall through to `*)`. That arm sends the reader to
  # "the warning above" for a run whose warning is three lines long and names a repair; more to the
  # point, `refreshed`'s line — "your own prose was left untouched" — is what this branch printed
  # before the decline existed, on runs that had just deleted the prose.
  malformed)
    CLAUDE_MD_STEP="$(marked_region_remedy "$CLAUDE_MD_MARKER_STATE" CLAUDE.md install.sh) Nothing was written to it this run."
    ;;
  *)
    CLAUDE_MD_STEP='CLAUDE.md generation was skipped — see the warning above.'
    ;;
esac
# Work this run was asked for and did not do. `Installation complete.` is true — the payload landed,
# the receipt is written — but on its own it read as "everything you asked for happened", and every
# abandonment left its only trace as warn lines up to five hundred lines above the green banner.
#
# THE BLOCK IS NOW THE `Not done:` CONTRACT MCP-SETUP.md STATES, not the manifest's private summary.
# The sites record into $NOT_DONE; this prints them. Derive their number where the accumulator is
# defined, and it writes no number down either. This sentence read "Twelve sites" for one round while
# the file's own header said eleven and forbade quoting the figure — in the place a reader tracing
# the mechanism arrives FIRST, which is how a stale count gets believed. The
# CLAUDE.md side is one of the sites now rather than the exception it used to be — it still ALSO
# rewrites `Next steps: 2.` in place, so a kept-yours or `separate` run says it twice, in the two
# places a reader looks.
#
# BEFORE `Next steps:`, DELIBERATELY. What a user does next depends on what did not happen, and a
# block printed after the numbered list reads as a footnote to it.
print_not_done
# THE LIST FORKS BY CLIENT, AND THREE OF THE FOUR CLAUDE-CODE STEPS WERE WRONG FOR A CODEX USER.
# Step 2 sent them to `CLAUDE.md`'s FILL: markers — the document Codex never loads — while the
# `AGENTS.md` it DOES load carries its own unfilled markers that nothing mentioned. Step 3 named the
# wrong binary and two slash commands this branch measured as having no surface at all. And step 1's
# destination, MCP-SETUP.md, listed "Claude Code (this CLI)" as a prerequisite.
#
# STEP 1 ON THE CODEX ARM IS THE ONE THAT DID NOT EXIST BEFORE. Project trust is the sixth
# silent-failure layer and the one a real user meets first: until `codex` has been run once in the
# project and its trust prompt accepted, `hooks/list` returns an EMPTY list — the hooks are not
# reported as untrusted, they are not registered at all, and nothing anywhere says so. `--codex-trust`
# grants PER-HOOK trust and cannot grant PROJECT trust, so a run whose `--codex-trust` succeeded
# still needs this. It used to be told only to the user whose trust step FAILED, which is precisely
# backwards: the failing run is loud, and the succeeding one is where the gap is silent.
if [ "$CLIENT" = codex ]; then
  case "${AGENTS_BRANCH:-skipped}" in
    written)    AGENTS_MD_STEP='Fill in the FILL: markers in AGENTS.md — genre, pillars, vision, scope. Codex injects that file whole; CLAUDE.md carries its own copy for Claude Code and is not read here.' ;;
    # THE STEP THAT CLOSES THE INSTRUCTION'S OWN LOOP. Step 2 tells the user to edit this file; until
    # 2026-08-17 the next run answered that edit with `Rename or delete it and re-run`, which is the
    # installer telling a user to throw away the work it had just asked for. A refreshed run says the
    # edit was kept and that the generated half is current, because both are now true.
    refreshed)  AGENTS_MD_STEP='AGENTS.md already had its generated section refreshed — the vision half you filled in was left untouched.' ;;
    # NOT `*)`. That arm says no entry document was generated, which is false of a project whose
    # AGENTS.md is on disk and merely a run behind on its facts.
    refresh-failed) AGENTS_MD_STEP='AGENTS.md was not refreshed this run — its generated section still carries an earlier run'"'"'s project facts, and the vision half you filled in was not touched. See the warning above.' ;;
    read-only)  AGENTS_MD_STEP='AGENTS.md is read-only, so this run left it exactly as it was. Make it writable (under Perforce: check it out) and re-run with --client codex.' ;;
    write-failed) AGENTS_MD_STEP='AGENTS.md could not be written this run — see the warning above. Any earlier one is still in place, a version behind.' ;;
    malformed)  AGENTS_MD_STEP="$(marked_region_remedy "$AGENTS_MARKER_STATE" AGENTS.md 'install.sh --client codex') Nothing was written to it this run." ;;
    kept-yours) AGENTS_MD_STEP='Your own AGENTS.md was kept, so no Codex entry document was generated. Rename or delete it and re-run with --client codex to get one.' ;;
    *)          AGENTS_MD_STEP='No AGENTS.md was generated this run — see the warning above. Without it, none of these conventions reach a Codex session.' ;;
  esac
cat <<EOF

Next steps:
  1. Grant PROJECT trust: run 'codex' once in this project and accept its trust prompt.
     Until you do, Codex registers no hooks here at all and reports no error about it.
  2. $AGENTS_MD_STEP
  3. Install the Unity MCP bridge — see MCP-SETUP.md, § "If your client is Codex CLI".
  4. Start 'codex' in your project and ask for a health check. There are no slash commands in
     Codex: the /unity-* content is installed as skills — read .agents/skills/<name>/SKILL.md.
  5. Health check any time: ./.claude/scripts/studio-doctor.sh --project-dir "$PROJECT_DIR"
EOF
else
cat <<EOF

Next steps:
  1. Install the Unity MCP bridge — see MCP-SETUP.md (Window > MCP for Unity > Auto-Setup).
  2. $CLAUDE_MD_STEP
  3. Run 'claude' in your project and try /unity-init, or /unity-doctor for a health check.
  4. Health check any time: ./.claude/scripts/studio-doctor.sh --project-dir "$PROJECT_DIR"
EOF
fi
exit 0
