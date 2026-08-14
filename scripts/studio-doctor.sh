#!/usr/bin/env bash
#
# Kinglet Pioneer — studio-doctor
#
# Health check for an installed toolkit and the environment it needs: Python/uv, the MCP bridge,
# settings.json wiring, and the integrity of the install itself.
#
# It verifies the install against .claude/state/install-receipt.tsv rather than looking for
# filenames it expects. That means it reports what actually happened — files gone missing, files you
# edited, files nobody installed — instead of just "present / not present".
#
# Usage:
#   ./scripts/studio-doctor.sh [--project-dir /path/to/UnityProject] [--toolkit-dir /path/to/kinglet]
#   In an installed Unity project this file is ./.claude/scripts/studio-doctor.sh — which is the
#   invocation install.sh's own closing "Next steps" prints, and the one most readers of this help
#   are actually holding.
#
# --toolkit-dir points at the kinglet-unity checkout this project was installed from. The receipt's
# origin column records that a file is yours; it cannot record that you have since put it back. With
# a checkout to compare against, a file whose bytes are once again the shipped ones is reported as
# reverted rather than as modified. Without one this check reads the column alone and says so rather
# than repeating a claim it cannot support. Run from a checkout it defaults to that checkout; run
# from ./.claude/scripts/ inside a project there is nothing to default to, which is the common case.
#
# Exits 1 if any check FAILs, 0 otherwise. (This used to always exit 0, which made it useless in CI.)
#
set -euo pipefail

if [ -t 1 ]; then
  RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[0;33m'; BOLD=$'\033[1m'; NC=$'\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; BOLD=''; NC=''
fi
PASS_C=0; WARN_C=0; FAIL_C=0
# A newline held in a variable, so no `$'…'` appears inside a parameter-expansion pattern below.
# install.sh carries the reasoning at its own `NL=`: bash 3.2's parser cannot be exercised from this
# host, a macOS pass is planned, and `"$NL"` inside the pattern is unambiguous in every bash. This
# file used to be install.sh's cited precedent for the risky spelling; both of its two sites were
# written on 2026-08-12 in the same wave that then chose against it, so the citation was to the
# wave's own code. Same idiom in both files now.
NL=$'\n'
pass() { printf '%s\n' "${GREEN}PASS${NC} $*"; PASS_C=$((PASS_C + 1)); }
warn() { printf '%s\n' "${YELLOW}WARN${NC} $*"; WARN_C=$((WARN_C + 1)); }
fail() { printf '%s\n' "${RED}FAIL${NC} $*"; FAIL_C=$((FAIL_C + 1)); }

# Print at most the first five entries of a newline-separated list, indented.
#
# NOT `printf '%s' "$LIST" | head -5`, which is what this replaced in both callers. Under
# `set -euo pipefail` head exits the instant it has five lines, without draining stdin; the writer
# takes SIGPIPE; pipefail promotes 141 to a pipeline failure; and `set -e` kills the script — before
# the payload-sanity checks, before the process-provider check, before the summary line, on exactly
# the long list that made the diagnostic worth printing. Measured 2026-08-12 on a receipt carrying
# 1200 modified rows: five paths printed, then exit 141 and nothing else. At 87 rows it survived,
# which is why every test written against a healthy project passed it.
#
# awk here reads its whole input and exits at EOF — there is no early exit to race with — and the
# here-string is a redirection, not a pipeline, so no writer process exists to receive a SIGPIPE and
# no pipeline status exists for pipefail to promote. The `NF` guard drops the trailing empty field
# the list's final newline produces.
print_first_5() {
  awk 'NF && NR <= 5 { printf "       %s\n", $0 }' <<< "$1"
}

usage() { sed -n '3,26p' "$0" | sed 's/^# \{0,1\}//'; exit 0; }

PROJECT_DIR="$(pwd)"
TOOLKIT_DIR=""
while [ $# -gt 0 ]; do
  case "$1" in
    --project-dir) [ $# -ge 2 ] || { printf 'err: --project-dir requires a path\n' >&2; exit 2; }
                   PROJECT_DIR="$2"; shift 2 ;;
    # Validated BEFORE `shift 2`, like --project-dir above: `shift 2` with one argument left fails
    # under `set -u` before any error message of ours can print, and the user gets a silent exit 1.
    --toolkit-dir) [ $# -ge 2 ] || { printf 'err: --toolkit-dir requires a path\n' >&2; exit 2; }
                   TOOLKIT_DIR="$2"; shift 2 ;;
    -h|--help)     usage ;;
    *)             printf 'Unknown argument: %s (use --help)\n' "$1" >&2; exit 2 ;;
  esac
done
PROJECT_DIR="$(cd "$PROJECT_DIR" 2>/dev/null && pwd)" || { printf 'Project directory not found.\n' >&2; exit 2; }
CLAUDE_DIR="$PROJECT_DIR/.claude"
RECEIPT="$CLAUDE_DIR/state/install-receipt.tsv"

# ── The toolkit checkout, when there is one to point at ──────────────────────
# An explicit --toolkit-dir is validated and refused loudly: a path that is not a checkout would
# otherwise silently supply no reference copy for anything, and the run would read exactly like one
# where the flag had never been passed — a flag that appears to work and changes nothing.
#
# THE DEFAULT IS DERIVED FROM WHERE THIS FILE IS, and it lands on the only shape that can answer.
# In a checkout this file is <repo>/scripts/studio-doctor.sh, so `dirname $0`/.. is the repo and
# carries .claude/VERSION. In an installed project it is <project>/.claude/scripts/studio-doctor.sh,
# so the same expression is <project>/.claude, which carries no .claude/VERSION of its own — no
# default, which is correct, because an installed project HAS no second copy to compare against.
#
# THE DEGENERATE CASE IS REFUSED IN BOTH BRANCHES, and it used to be refused in only one. A toolkit
# directory that IS the project makes every file trivially equal to itself, so EVERY `user-modified`
# row reports as reverted — the exact direction the classifier arm below forbids, because telling a
# user their work is not at risk when it is, is the one wrong answer that costs something. Measured
# 2026-08-14 on a project with a live, uncommitted edit: `--toolkit-dir <checkout>` correctly said
# `1 file(s) modified since install`, and `--toolkit-dir <the project>` said `1 file(s) recorded as
# yours are byte-identical to this toolkit's copy` and `You put them back.`
#
# The `else` branch below has always declined it, silently, because a default that does not resolve
# is not an error. An EXPLICIT flag is different: the user asked for a comparison, and the honest
# answer is that this one cannot be made — so it exits 2 like the other two argument failures rather
# than falling back to a bare run whose output would look nothing like what they asked for.
if [ -n "$TOOLKIT_DIR" ]; then
  TOOLKIT_DIR="$(cd "$TOOLKIT_DIR" 2>/dev/null && pwd)" || { printf 'Toolkit directory not found.\n' >&2; exit 2; }
  [ -f "$TOOLKIT_DIR/.claude/VERSION" ] \
    || { printf 'Not a kinglet-unity checkout (no .claude/VERSION): %s\n' "$TOOLKIT_DIR" >&2; exit 2; }
  # `printf '%s\n' "--toolkit-dir …"`, never `printf -- '--toolkit-dir …'`: a format string starting
  # with `-` is read as an option by bash's builtin printf, which reported
  # `printf: --: invalid option` on the very line meant to explain the refusal. The message is data,
  # so it travels as an argument.
  #
  # `-ef` (SAME DEVICE AND INODE), NOT `!=`, AND THE DIFFERENCE IS A WHOLE CLASS. Both sides have
  # been through `cd`+`pwd`, but that resolution is LOGICAL, not physical: `cd <symlink-to-project>
  # && pwd` prints the symlink's own path where `pwd -P` would print the project's. A string
  # comparison therefore catches only textual spellings, and four aliases walked straight past it —
  # measured 2026-08-14 on a project holding a live edit, each rc=0, unrefused, and each reporting
  # that edit as reverted: a symlink passed as --toolkit-dir, the project passed as that symlink, and
  # either side reached through a symlinked parent. `-ef` compares what the two names actually point
  # at, so every spelling of one directory is one directory. It is a `test` primary in bash and in
  # POSIX, so it is safe on 3.2. Asserted in tests/test-doctor-reverted.sh's assertion 9.
  [ ! "$TOOLKIT_DIR" -ef "$PROJECT_DIR" ] \
    || { printf '%s\n' "--toolkit-dir is the project itself: $TOOLKIT_DIR" >&2
         printf '%s\n' "Every file would equal itself, so every file you have edited would be reported as put back." >&2
         exit 2; }
else
  # `-ef` here too, for the same reason and to keep the two branches one rule rather than two. This
  # side declines silently — a default that does not resolve is not an error — but it must decline
  # the same set the explicit branch refuses, or the guard's coverage depends on which way the user
  # invoked it.
  TOOLKIT_CAND="$(cd "$(dirname "$0")/.." 2>/dev/null && pwd)" || TOOLKIT_CAND=""
  if [ -n "$TOOLKIT_CAND" ] && [ -f "$TOOLKIT_CAND/.claude/VERSION" ] && [ ! "$TOOLKIT_CAND" -ef "$PROJECT_DIR" ]; then
    TOOLKIT_DIR="$TOOLKIT_CAND"
  fi
fi

# toolkit_ref <project-relative path> — the toolkit's shipped copy of that path, or nothing.
#
# MIRRORS install.sh'S TWO WRITE LOOPS AND HAS TO KEEP MIRRORING THEM. Step 5's payload loop takes
# `.claude/<rel>` from `<checkout>/.claude/<rel>`; the scripts loop takes `.claude/scripts/<name>`
# from the repo-root `<checkout>/scripts/<name>`, because no `.claude/scripts/` exists in the
# checkout at all. Anchor: the `user-modified)` arm of install.sh's MODIFIED_FILES loop carries the
# same two-arm case and the reasoning behind it. One arm instead of two would make every
# `.claude/scripts/*` row look referenceless, and a referenceless row is reported as still-modified —
# wrong in the quiet direction.
#
# Returns 0 on every path, including the no-match one: the caller does `REF="$(toolkit_ref "$rel")"`,
# a bare assignment, where a non-zero status is a `set -e` kill in the middle of the receipt loop.
toolkit_ref() {
  [ -n "$TOOLKIT_DIR" ] || return 0
  case "$1" in
    .claude/scripts/*) printf '%s/scripts/%s' "$TOOLKIT_DIR" "${1#.claude/scripts/}" ;;
    .claude/*)         printf '%s/.claude/%s' "$TOOLKIT_DIR" "${1#.claude/}" ;;
  esac
  return 0
}

printf '%s\n' "${BOLD}Kinglet Pioneer — studio-doctor${NC}"
printf 'Project: %s\n' "$PROJECT_DIR"
if [ -f "$CLAUDE_DIR/VERSION" ]; then
  VER=$(cat "$CLAUDE_DIR/VERSION")
  ECU_VER=$(sed -n 's/^ecu=//p' "$CLAUDE_DIR/UPSTREAM" 2>/dev/null || echo '?')
  printf 'Installed: Kinglet Pioneer %s (vendored ECU %s)\n' "$VER" "$ECU_VER"
fi
printf '\n'

# ── Environment: Python 3.10+ ────────────────────────────────────────────────
PY=""
command -v python3 >/dev/null 2>&1 && PY=python3
[ -z "$PY" ] && command -v python >/dev/null 2>&1 && PY=python
if [ -z "$PY" ]; then
  warn "Python not found. The MCP bridge needs Python 3.10+."
elif "$PY" -c 'import sys; sys.exit(0 if sys.version_info >= (3,10) else 1)' 2>/dev/null; then
  pass "Python $("$PY" -c 'import sys; print("%d.%d"%sys.version_info[:2])') (3.10+ required)"
else
  warn "Python $("$PY" -c 'import sys; print("%d.%d"%sys.version_info[:2])' 2>/dev/null) is too old — the MCP bridge needs 3.10+."
fi

# ── Environment: uv ──────────────────────────────────────────────────────────
if command -v uv >/dev/null 2>&1; then
  # First line only, via parameter expansion rather than `| head -1` — see print_first_5. `uv
  # --version` prints one line today, so this pipe was unlikely to fire, but the shape is the same
  # one and the spec's criterion 12 admits no `| head` in this file.
  UV_VER=$(uv --version 2>/dev/null || true); UV_VER=${UV_VER%%"$NL"*}
  pass "uv present ($UV_VER)"
else
  warn "uv not found — the MCP bridge runs under it. See https://docs.astral.sh/uv/"
fi

# ── MCP bridge reachable — and actually an MCP bridge ────────────────────────
#
# This used to be `curl -fsS http://localhost:8080/mcp` and passed on ANY HTTP response. On a machine
# where 8080 happened to be an unrelated nginx, it cheerfully reported "MCP bridge responding" at a
# web server that has never heard of Unity. That is the same defect as testing settings.json with a
# bare `grep unityMCP`: it proves something answered, not that the right thing answered.
#
# So: read the endpoint from the project's own config rather than hardcoding a port, then speak
# JSON-RPC and require an MCP-shaped reply.
read_mcp_url() {
  local f url=""
  # settings.local.json wins — that is where a machine-local port override belongs. .mcp.json is
  # where install.sh actually writes the server config (Task 2 moved it there because Claude Code
  # never read mcpServers out of settings.json); settings.json is kept as a last-resort fallback
  # for older installs that still have it there.
  for f in "$CLAUDE_DIR/settings.local.json" "$PROJECT_DIR/.mcp.json" "$CLAUDE_DIR/settings.json"; do
    [ -f "$f" ] || continue
    if command -v jq >/dev/null 2>&1; then
      # UnityMCP (capital U) is what install.sh writes and what CoplayDev's Auto-Setup registers —
      # see provenance.tsv and tests/test-mcp-naming.sh. unityMCP (lowercase) is read as a fallback
      # so an older project's untouched .mcp.json still gets checked instead of reporting missing.
      url=$(jq -r '.mcpServers.UnityMCP.url // .mcpServers.unityMCP.url // empty' "$f" 2>/dev/null || true)
    elif [ -n "$PY" ]; then
      url=$("$PY" -c 'import json,sys
try:
    servers = json.load(open(sys.argv[1])).get("mcpServers",{})
    print(servers.get("UnityMCP",{}).get("url","") or servers.get("unityMCP",{}).get("url",""))
except Exception: pass' "$f" 2>/dev/null || true)
    fi
    if [ -n "$url" ]; then
      printf '%s' "$url"
      return 0
    fi
  done
  # Nothing matched. This must return 0: the caller does `MCP_URL=$(read_mcp_url)` under `set -e`,
  # and a bare fall-through here would return the exit status of the last `[ -n "$url" ] && { ... }`
  # — false — which kills the whole script two checks in and reports success on a project it never
  # examined the rest of. Returning 1 is a real failure; "no URL configured" is not one, it is a
  # WARN the caller already prints.
  return 0
}

MCP_URL=$(read_mcp_url)
if [ -z "$MCP_URL" ]; then
  warn "No mcpServers.UnityMCP.url in settings — skipped the bridge check."
elif ! command -v curl >/dev/null 2>&1; then
  warn "curl not found — skipped the bridge check."
else
  # A real MCP server answers initialize with a JSON-RPC result naming itself. Streamable HTTP wants
  # both content types in Accept.
  MCP_REQ='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"studio-doctor","version":"1"}}}'
  MCP_RESP=$(curl -sS --max-time 5 -X POST "$MCP_URL" \
      -H 'Content-Type: application/json' \
      -H 'Accept: application/json, text/event-stream' \
      -d "$MCP_REQ" 2>/dev/null || true)
  if [ -z "$MCP_RESP" ]; then
    warn "Nothing answered at $MCP_URL — open Unity and start the bridge (Window > MCP for Unity)."
  elif grep -q '"jsonrpc"' <<< "$MCP_RESP"; then
    # sed reads a here-string to EOF and the first line is taken by parameter expansion. This was
    # `printf '%s' "$MCP_RESP" | sed -n '...' | head -1`, and it is the worst of the four instances of
    # that shape in this file, because it is a bare assignment: a 141 from the pipeline becomes the
    # assignment's status and `set -e` kills the script here, at the bridge check, so every check
    # below — .mcp.json, the input package, install integrity, payload sanity, the process provider,
    # the summary — never runs. It fires when sed emits more lines than head will read, which an
    # Accept of text/event-stream invites: a streamed reply is many `data:` lines, each carrying
    # serverInfo. Measured 2026-08-12: 3 matching lines survived 5/5, 100 survived 5/5, 1000 died
    # 5/5. Whether a real bridge sends a thousand is not the point — the failure is silent and total.
    SRV=$(sed -n 's/.*"serverInfo"[^{]*{[^}]*"name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' <<< "$MCP_RESP")
    SRV=${SRV%%"$NL"*}
    pass "MCP bridge answered at $MCP_URL${SRV:+ (${SRV})}"
  else
    # Something is listening, but it is not an MCP server. Say so — do not call it a bridge.
    fail "$MCP_URL is serving something that is NOT an MCP server."
    printf '     %s\n' "first bytes: $(printf '%s' "$MCP_RESP" | tr -d '\n' | cut -c1-70)"
    printf '     %s\n' "Another service holds that port. Point UnityMCP at a free one in .claude/settings.local.json."
  fi
fi

# ── .mcp.json wiring (parsed, not grepped) ───────────────────────────────────
# This used to check .claude/settings.json — that was correct before Task 2, which moved the
# mcpServers key to .mcp.json at the project root because Claude Code never read it out of
# settings.json. Left pointed at settings.json, this check would FAIL every healthy install, since
# a correct install no longer puts mcpServers there at all. Check the file install.sh actually
# writes. The old check was also `grep -q unityMCP`, which passes on the word appearing in a
# comment or an unrelated key — the user can edit this file, so it gets a real parse.
MCP_JSON="$PROJECT_DIR/.mcp.json"
SETTINGS="$CLAUDE_DIR/settings.json"
if [ ! -f "$MCP_JSON" ]; then
  fail "No .mcp.json at project root — run install.sh."
else
  MCP_CONFIGURED=""
  MCP_CONFIGURED_KEY=""
  if command -v jq >/dev/null 2>&1; then
    MCP_CONFIGURED=$(jq -r '.mcpServers.UnityMCP.url // .mcpServers.unityMCP.url // empty' "$MCP_JSON" 2>/dev/null || true)
    MCP_CONFIGURED_KEY=$(jq -r 'if .mcpServers.UnityMCP then "UnityMCP" elif .mcpServers.unityMCP then "unityMCP" else empty end' "$MCP_JSON" 2>/dev/null || true)
  elif [ -n "$PY" ]; then
    MCP_CONFIGURED=$("$PY" -c 'import json,sys
try:
    servers = json.load(open(sys.argv[1])).get("mcpServers", {})
    print(servers.get("UnityMCP", {}).get("url", "") or servers.get("unityMCP", {}).get("url", ""))
except Exception:
    pass' "$MCP_JSON" 2>/dev/null || true)
    MCP_CONFIGURED_KEY=$("$PY" -c 'import json,sys
try:
    servers = json.load(open(sys.argv[1])).get("mcpServers", {})
    print("UnityMCP" if "UnityMCP" in servers else ("unityMCP" if "unityMCP" in servers else ""))
except Exception:
    pass' "$MCP_JSON" 2>/dev/null || true)
  fi
  if [ -n "$MCP_CONFIGURED" ]; then
    # Say which file actually wins. Reporting .mcp.json's URL while the probe above used a
    # different one from settings.local.json is two lines contradicting each other about the same
    # fact — the reader has to guess which is live.
    if [ -n "$MCP_URL" ] && [ "$MCP_URL" != "$MCP_CONFIGURED" ]; then
      pass ".mcp.json: ${MCP_CONFIGURED_KEY} → $MCP_CONFIGURED (overridden by settings.local.json → $MCP_URL)"
    else
      pass ".mcp.json: mcpServers.${MCP_CONFIGURED_KEY} → $MCP_CONFIGURED"
    fi
  elif command -v jq >/dev/null 2>&1 || [ -n "$PY" ]; then
    fail ".mcp.json has no mcpServers.UnityMCP.url — MCP tools will not work."
  else
    warn "Neither jq nor python available — could not parse .mcp.json."
  fi
fi

# ── New Input System package ─────────────────────────────────────────────────
# unity-specifics.md makes it non-negotiable and block-legacy-input.sh blocks the legacy API, but
# neither one checks that com.unity.inputsystem is actually installed. A project missing it cannot
# compile the first script written under its own rules, and that compile error also aborts Unity's
# -executeMethod, so Editor automation stops too (smoke-pass.md §6c). install.sh warns about this at
# install time; this lets an already-installed project find out without reinstalling.
INPUT_SYSTEM_PKG_NAME="com.unity.inputsystem"
MANIFEST="$PROJECT_DIR/Packages/manifest.json"
if [ ! -f "$MANIFEST" ]; then
  warn "No Packages/manifest.json — could not check for $INPUT_SYSTEM_PKG_NAME."
elif grep -q "$INPUT_SYSTEM_PKG_NAME" "$MANIFEST"; then
  pass "$INPUT_SYSTEM_PKG_NAME present in manifest.json"
else
  warn "$INPUT_SYSTEM_PKG_NAME is missing. unity-specifics.md makes the New Input System"
  warn "     non-negotiable and blocks legacy Input.* — the first script written under this"
  warn "     toolkit's own rules will fail to compile without it."
  warn "     Re-run install.sh --with-input-system to add it, or add it to manifest.json yourself."
fi

# ── Install integrity, against the receipt ───────────────────────────────────
if [ ! -d "$CLAUDE_DIR" ]; then
  fail "No .claude/ directory — run install.sh --project-dir \"$PROJECT_DIR\"."
elif [ ! -f "$RECEIPT" ]; then
  warn "No install receipt. .claude/ exists but Kinglet did not write it here"
  warn "     (a teammate's git clone will look like this — the receipt is machine-local)."
else
  # TWO TESTS, NOT ONE — the same grammar uninstall.sh's classifier uses, deliberately, so that one
  # reading of the origin column covers both readers instead of two that drift apart.
  #
  # `user-modified` means a previous install found your edit and kept it, recording the file AS
  # EDITED so the NEXT install still recognises it as yours. The checksum on such a row is therefore
  # the checksum of YOUR file, and a sha-only comparison always matches. That is how this check came
  # to report `PASS Install intact: 87 file(s) verified against the receipt` about a project whose
  # rules file the user had rewritten — the diagnostic telling them nothing had changed about the one
  # file they changed. Reproduced on a fixture 2026-08-12 before this was written.
  #
  # The sha test is right for `toolkit` rows and only for them: there it separates "we installed it
  # and nobody touched it" from an edit made AFTER the last install, which is the only kind a
  # `toolkit` row can express.
  #
  # AN ORIGIN WE CANNOT READ IS REPORTED, NOT COUNTED VERIFIED — AND REPORTED ON ITS OWN LINE. `case`
  # with an explicit catch-all rather than an if/elif that lets anything unrecognised fall through to
  # the sha test: a row with a trailing space, a CRLF ending or a fifth column is no longer byte-equal
  # to `user-modified`, and under a fall-through it would be silently certified. A file whose
  # provenance cannot be read is not ours to certify.
  #
  # It is not ours to summarise, either, and this comment claimed otherwise until 2026-08-13: it said
  # install.sh and uninstall.sh would "both leave that file alone", and the third bucket was printed
  # under `modified since install — install.sh will keep your versions`. Half of that was false, and
  # the block that replaced it described install.sh as an if/else that let an unreadable origin fall
  # through to the sha test, so a mangled column on a file whose bytes still matched meant the
  # payload loop OVERWROTE the user's edit with no `keeping yours` line. That was measured, and it
  # was true until 2026-08-14. **It is no longer true, and this paragraph is the correction rather
  # than the finding** — the citation it carried, `grep -n 'if \[ "$origin" = user-modified \]'
  # install.sh`, now returns nothing.
  #
  # WHERE THE FOUR READERS OF THIS COLUMN STAND TODAY. Two of them trim surrounding whitespace before
  # comparing; two do not and are fail-closed by a `case` catch-all instead:
  #
  #   install.sh, owned_by_installer      — TRIMS, then requires exactly `toolkit` to re-claim a file.
  #   install.sh, the MODIFIED_FILES loop — TRIMS, then a `case`. `user-modified` keeps the file;
  #                                         anything unreadable ALSO keeps it and is reported on its
  #                                         own line. This is the reader that used to destroy edits.
  #   uninstall.sh's classifier           — DOES NOT TRIM. `case` with a keeping `*)`, so a mangled
  #                                         `user-modified` is safe — but a mangled `toolkit ` on an
  #                                         UNEDITED file is classified as the user's and never
  #                                         removed. That mirror is still open on that side.
  #   this file                           — DOES NOT TRIM. Same `case` shape, reporting only. Since
  #                                         2026-08-14 the column no longer DECIDES for a
  #                                         `user-modified` row: it selects the row for a byte
  #                                         comparison against the toolkit's shipped copy, when
  #                                         --toolkit-dir names one. A row with no reference copy is
  #                                         still decided by the column, and the report says which.
  #
  # So `install.sh will keep your versions` is now true of every bucket this loop can produce. These
  # rows still get their own line, for the reason that outlives the fix: this file writes nothing and
  # cannot certify a provenance it cannot read, and folding them into MODIFIED would put two
  # different situations under one count. What changed is that the separation is no longer reporting
  # a disagreement between the two writers — they agree now.
  #
  # The sha comparison stays fail-closed the same way uninstall.sh's `sha_of` is: an unreadable file
  # yields the empty string, which never equals a recorded checksum, so the row lands in MODIFIED and
  # is reported rather than silently passed.
  VERIFIED=0; MODIFIED=0; MISSING=0; UNREADABLE=0; REVERTED=0; STICKY=0
  MODIFIED_LIST=""; MISSING_LIST=""; UNREADABLE_LIST=""; REVERTED_LIST=""
  while IFS=$'\t' read -r rel recorded _mode origin; do
    case "$rel" in ''|\#*|path) continue ;; esac
    abs="$PROJECT_DIR/$rel"
    if [ ! -f "$abs" ]; then
      MISSING=$((MISSING + 1)); MISSING_LIST="${MISSING_LIST}${rel}"$'\n'
      continue
    fi
    case "$origin" in
      user-modified)
        # A `user-modified` ROW IS A RECORD OF WHAT A PAST RUN FOUND, NOT OF WHAT IS ON DISK NOW, and
        # this arm classified by the column alone until 2026-08-14 — no bytes were ever compared. So
        # a file the user had put back to the shipped text was reported under `modified since
        # install` forever: measured that day on a --variant urp fixture, install → edit → install →
        # revert to the toolkit's exact bytes, `WARN 1 file(s) modified since install` about a file
        # byte-identical to the toolkit's own copy.
        #
        # THE SHA ON THE ROW CANNOT ANSWER THIS, WHICH IS WHY THE REFERENCE COPY IS NEEDED. The row
        # records the file AS EDITED, so `$2` matched the edited bytes; after a further install it
        # records the REVERTED bytes and matches those instead. Either way a row-versus-disk
        # comparison says "unchanged" and says nothing about whose the file is. Only the toolkit's
        # shipped copy discriminates, and install.sh's fix for the same defect makes exactly this
        # comparison — deliberately the same one, so the installer and this check cannot drift into
        # disagreeing about the same file.
        #
        # WITH NO CHECKOUT TO POINT AT, NOTHING IS PROVED AND THE FILE STAYS IN MODIFIED. That is the
        # fail-closed direction: reporting an edit that has been reverted costs a stale warning;
        # reporting a live edit as reverted tells the user their work is not at risk when it is. The
        # count of rows that took this branch unproved is kept so the report can say so out loud
        # rather than leaving the reader to assume the bytes were looked at.
        REF="$(toolkit_ref "$rel")"
        REF_HAVE=""; REF_WANT=""
        if [ -n "$REF" ] && [ -f "$REF" ]; then
          REF_HAVE="$(sha256sum "$abs" 2>/dev/null | cut -d' ' -f1 || true)"
          REF_WANT="$(sha256sum "$REF" 2>/dev/null | cut -d' ' -f1 || true)"
        fi
        # `-n "$REF_HAVE"` is load-bearing: an unreadable file and an unreadable reference both hash
        # to the empty string, and without this an I/O error on both sides would read as a match.
        if [ -n "$REF_HAVE" ] && [ "$REF_HAVE" = "$REF_WANT" ]; then
          REVERTED=$((REVERTED + 1)); REVERTED_LIST="${REVERTED_LIST}${rel}"$'\n'
        else
          MODIFIED=$((MODIFIED + 1)); MODIFIED_LIST="${MODIFIED_LIST}${rel}"$'\n'
          # COUNTED ON THE REFERENCE, NOT ON THE HASH, because the report says `no shipped copy to
          # compare against` and that has to be true of every row it counts. An UNREADABLE project
          # file also yields an empty hash — measured 2026-08-14 with a payload file at mode 000 —
          # and it has a shipped copy; it lands in MODIFIED for the same fail-closed reason the
          # `toolkit` arm below puts it there, and is not claimed to be a row nobody could source.
          #
          # `if`, not `[ -n … ] || STICKY=…`: a test as the last command of a loop body is a `set -e`
          # kill whenever it is false, and the `||` form only escapes that by accident of the
          # assignment always succeeding. The next edit to this arm should not have to know that.
          if [ -z "$REF" ] || [ ! -f "$REF" ]; then STICKY=$((STICKY + 1)); fi
        fi
        ;;
      toolkit)
        if [ "$(sha256sum "$abs" 2>/dev/null | cut -d' ' -f1)" = "$recorded" ]; then
          VERIFIED=$((VERIFIED + 1))
        else
          MODIFIED=$((MODIFIED + 1)); MODIFIED_LIST="${MODIFIED_LIST}${rel}"$'\n'
        fi
        ;;
      *)
        UNREADABLE=$((UNREADABLE + 1)); UNREADABLE_LIST="${UNREADABLE_LIST}${rel}"$'\n'
        ;;
    esac
  done < <(grep -v '^#' "$RECEIPT")

  if [ "$MISSING" -eq 0 ]; then
    pass "Install intact: $VERIFIED file(s) verified against the receipt"
  else
    fail "$MISSING receipted file(s) missing — re-run install.sh"
    print_first_5 "$MISSING_LIST"
  fi
  if [ "$MODIFIED" -gt 0 ]; then
    # Not a failure. Editing the toolkit in place is legitimate; you just want to know you did,
    # because re-install will keep these and upstream fixes will not reach them.
    #
    # The sentence is true of both branches that feed this list, and of neither more than the other:
    # a `user-modified` row is kept by install.sh's first test, a `toolkit` row whose bytes drifted is
    # kept by its second. The third bucket used to be here too and is not kept — see the classifier's
    # comment above.
    warn "$MODIFIED file(s) modified since install — install.sh will keep your versions:"
    print_first_5 "$MODIFIED_LIST"
    # WHAT THIS COUNT IS BUILT FROM, WHEN PART OF IT IS BUILT FROM AN ASSUMPTION. A `toolkit` row in
    # this list was decided by comparing bytes. A `user-modified` row with no shipped copy to compare
    # against was decided by the column alone, and the column cannot know the file was put back. The
    # line above is a claim about both; these lines are the boundary of the evidence behind it, and
    # printing the number rather than a hedge is what makes it checkable.
    if [ "$STICKY" -gt 0 ]; then
      warn "     $STICKY of those carry a 'user-modified' row with no shipped copy to compare against,"
      warn "     so the receipt's origin column alone put them here — a file you have PUT BACK reads"
      warn "     exactly like one you are still editing."
      if [ -z "$TOOLKIT_DIR" ]; then
        warn "     Re-run with --toolkit-dir <kinglet-unity checkout> to tell the two apart."
      fi
    fi
  fi
  if [ "$REVERTED" -gt 0 ]; then
    # NOT A FAILURE AND NOT A PASS. Nothing is broken — the bytes on disk are this toolkit's own —
    # but the receipt still claims the file as the user's, and while it does, install.sh keeps it
    # rather than delivering later versions of it. That is a real, actionable staleness with a
    # one-command remedy, which is what `warn` is for here. It stops being true after one install:
    # install.sh's MODIFIED_FILES loop makes the same comparison and rewrites the row `toolkit`.
    warn "$REVERTED file(s) recorded as yours are byte-identical to this toolkit's copy:"
    print_first_5 "$REVERTED_LIST"
    warn "     You put them back. Until the next install.sh run rewrites those rows, this project is"
    warn "     still cut off from updates to them."
  fi
  if [ "$UNREADABLE" -gt 0 ]; then
    # Also not a failure, and deliberately not a claim about what happens to the file next. The
    # receipt carries more than one class of row and the write paths differ — measured 2026-08-13 on
    # fixtures whose receipt row was mangled to `toolkit ` after the first install:
    #
    #   .claude/** payload rows      — Step 5's payload loops write them unless is_modified says
    #                                  otherwise, so the upgrade scan's sha test decides: bytes
    #                                  unchanged → overwritten, bytes drifted → kept. (Measured with
    #                                  the toolkit's own copy of the file bumped between the two
    #                                  installs, so an overwrite would show.)
    #   MCP-SETUP.md, .mcp.json      — Step 8b/8c write them ONLY when absent (`[ ! -f ]`), so the
    #                                  file is untouched either way. What the column costs there is
    #                                  the ROW: `owned_by_installer` tries the toolkit's reference
    #                                  copy first and the receipt second, and its `$4 == "toolkit"`
    #                                  test fails on a mangled origin, so the row is dropped. The file
    #                                  silently stops being owned and uninstall.sh stops removing it.
    #
    # BOTH root files behave that way, and an earlier revision of this comment said they did not.
    # That claim came from a two-variable comparison and is withdrawn: MCP-SETUP.md's reference IS a
    # shipped file, so bumping it is what forces owned_by_installer past its first arm, while
    # .mcp.json has no shipped copy at all — its reference is the heredoc at
    # `grep -n 'cat > "$MCP_JSON_REF"' install.sh`, regenerated byte-identically every run, so that
    # first arm kept matching and the receipt was never consulted. Bump the heredoc between the two
    # installs and .mcp.json drops its row exactly as MCP-SETUP.md does: clean origin KEPT, mangled
    # origin DROPPED, one variable apart. A drifted-bytes fixture proves nothing about the column
    # either way, because `$2 == have` fails first and drops the row on a clean origin too.
    #
    # Two different readers, and only one of them ignores the column: install.sh's UPGRADE SCAN
    # classifies by bytes and not by this column, which is what the line below says; owned_by_installer
    # does read it, which is what costs root rows their ownership. Repairing that asymmetry is
    # install.sh's job, not this file's.
    warn "$UNREADABLE file(s) have a receipt origin this check does not recognise — reported, not verified:"
    print_first_5 "$UNREADABLE_LIST"
    warn "     Neither toolkit nor user-modified in the receipt's fourth column. uninstall.sh keeps"
    warn "     such a file; install.sh classifies it by bytes and not by that column, and what that"
    warn "     means for the file depends on which write path its row is on."
  fi
fi

# ── Payload sanity ───────────────────────────────────────────────────────────
if [ -d "$CLAUDE_DIR" ]; then
  # THE OTHER HALF OF THE PIPEFAIL TRAP, and the half no needle in the suite looks for. Everything
  # else in this wave is about a READER that exits early and SIGPIPEs its writer. Here the WRITER
  # fails and pipefail promotes THAT: `find` returns 1 for a path that does not exist, and
  # `2>/dev/null` hides the message, not the status. `wc -l` still prints the correct `0`, so the
  # VALUE was never wrong — only the pipeline's status, which a bare assignment under `set -e` acts
  # on. Same consequence as SIGPIPE, opposite cause.
  #
  # The `if [ -d "$CLAUDE_DIR" ]` above is not the guard it looks like: it establishes the PARENT,
  # and these four walk CHILDREN it says nothing about. Measured 2026-08-14 on a project with
  # `.claude/` but no `.claude/agents/` — this health check died right here at rc=1 with no INFO
  # line, no NOTICE.md check, no hook-existence check and NO SUMMARY. The toolkit's own diagnostic,
  # dying on exactly the broken install it exists to diagnose.
  #
  # `|| true` rather than a `[ -d ]` per line: the count is already correct in every case, so there
  # is nothing to repair but the status. It does also absorb a genuine mid-walk failure (a
  # permission error deep in the tree), whose cost is an undercount reported as a count — acceptable
  # here, because the alternative on today's code is no number and no report at all.
  #
  # uninstall.sh carries the same `find … | wc -l | tr` shape and does NOT need this: its guard is
  # `if [ -d "$CLAUDE_DIR" ]` on the line immediately above it and it walks that same directory.
  A=$(find "$CLAUDE_DIR/agents" -name '*.md' 2>/dev/null | wc -l | tr -d ' ' || true)
  C=$(find "$CLAUDE_DIR/commands" -name '*.md' 2>/dev/null | wc -l | tr -d ' ' || true)
  S=$(find "$CLAUDE_DIR/skills" -name 'SKILL.md' 2>/dev/null | wc -l | tr -d ' ' || true)
  R=$(find "$CLAUDE_DIR/rules" -name '*.md' 2>/dev/null | wc -l | tr -d ' ' || true)
  printf 'INFO agents=%s commands=%s skills=%s rules=%s\n' "$A" "$C" "$S" "$R"

  # ── The payload directories, as a VERDICT and not as four numbers ──────────
  #
  # THE COUNTS ABOVE ARE NOT A FINDING A READER CAN ACT ON, AND FOR TWO OF THE FIVE DIRECTORIES THEY
  # ARE NOT PRINTED AT ALL. `.claude/hooks/` is walked nowhere above; `.claude/agents/` is walked and
  # its count is printed as INFO, which no reader maps to WARN or FAIL. Measured 2026-08-14 on a
  # --variant urp fixture with the receipt removed — the teammate's-git-clone shape this file's own
  # receipt branch names, where the receipt cannot notice the files are gone:
  #
  #   `.claude/agents/*.md` deleted → `INFO agents=0`, `0 failure(s)`, exit 0.
  #   `.claude/rules/` deleted      → `INFO rules=0`,  `0 failure(s)`, exit 0.
  #
  # A project with no agents at all, and a project with none of the five binding spine rules, both
  # certified healthy by the toolkit's own health check. `/unity-doctor` carried a hand-written
  # compensation for exactly this — "read those four numbers yourself: any zero is this item's
  # ERROR" — which is a check performed by a model against a script that was already holding the
  # answer. The script issues the verdict now and that item is deleted rather than kept alongside.
  #
  # PRESENT-BUT-EMPTY IS A SEPARATE STATE FROM MISSING and both are reported, because they arrive by
  # different routes: an interrupted install, a partial `git rm`, or a `.gitignore` that swallowed a
  # payload directory's contents leaves the directory itself behind. A bare `[ -d ]` existence test
  # passes on all of them.
  #
  # WHY `fail` AND NOT `warn`: a payload directory with nothing in it is not a degraded install, it
  # is a surface the model cannot reach at all — an empty `.claude/rules/` means every spine rule
  # this toolkit binds on is absent from the project while `.claude/` looks installed.
  #
  # The glob per directory is the one that makes a file COUNT there: skills are directories, so the
  # payload file is `<name>/SKILL.md`, and a `.claude/skills/` holding empty directories holds no
  # skills. Same `find … | wc -l` shape as the counts above, `|| true` inside the substitution for
  # the same reason.
  PAYLOAD_BAD=0
  for pd_spec in "agents:*.md" "commands:*.md" "hooks:*.sh" "rules:*.md" "skills:SKILL.md"; do
    pd_name="${pd_spec%%:*}"
    pd_glob="${pd_spec#*:}"
    if [ ! -d "$CLAUDE_DIR/$pd_name" ]; then
      fail "Payload directory .claude/$pd_name/ is missing — re-run install.sh --project-dir \"$PROJECT_DIR\""
      PAYLOAD_BAD=$((PAYLOAD_BAD + 1))
    else
      pd_n=$(find "$CLAUDE_DIR/$pd_name" -name "$pd_glob" 2>/dev/null | wc -l | tr -d ' ' || true)
      if [ "$pd_n" -eq 0 ]; then
        fail "Payload directory .claude/$pd_name/ is present but holds no $pd_glob — re-run install.sh --project-dir \"$PROJECT_DIR\""
        PAYLOAD_BAD=$((PAYLOAD_BAD + 1))
      fi
    fi
  done
  # `if`, not `[ … ] && pass …`: a false test as the last command of this block is a status the next
  # edit should not have to reason about. Same choice, same reason, as the STICKY arm above.
  if [ "$PAYLOAD_BAD" -eq 0 ]; then
    pass "Payload complete: agents, commands, hooks, rules and skills all present and non-empty"
  fi

  [ -f "$CLAUDE_DIR/NOTICE.md" ] && pass "NOTICE.md present (third-party licenses travel with the copy)" \
                                 || fail "NOTICE.md missing — the vendored MIT notices must ship with .claude/"
  # Every hook settings.json references must exist, or the hook silently never fires.
  if [ -f "$SETTINGS" ]; then
    BROKEN=0
    for h in $(grep -oE '\.claude/hooks/[a-z_-]+\.sh' "$SETTINGS" 2>/dev/null | sort -u); do
      [ -f "$PROJECT_DIR/$h" ] || { fail "settings.json references a missing hook: $h"; BROKEN=$((BROKEN + 1)); }
    done
    [ "$BROKEN" -eq 0 ] && pass "All hooks referenced by settings.json exist"
  fi
fi

# ── Declared process provider still installed? ─────────────────────────────
# A declaration that is no longer true is a warning, not a failure: the project
# still works, and doctor's job here is to offer the built-in provider as an
# explicit fallback rather than to block.
CLAUDE_MD="$PROJECT_DIR/CLAUDE.md"
USER_SETTINGS="${KINGLET_USER_SETTINGS:-$HOME/.claude/settings.json}"
if [ -f "$CLAUDE_MD" ] && grep -q '^### Process provider' "$CLAUDE_MD"; then
    declared=$(awk '/^### Process provider/{f=1} f && /owned by/{
        if (match($0, /`[^`]+`/)) print substr($0, RSTART+1, RLENGTH-2); exit }' "$CLAUDE_MD")
    if [ -z "$declared" ]; then
        warn "CLAUDE.md has a Process provider section but names no provider."
    elif [ -f "$USER_SETTINGS" ] && grep -q "\"$declared@[^\"]*\"[[:space:]]*:[[:space:]]*true" "$USER_SETTINGS"; then
        pass "declared process provider '$declared' is installed"
    else
        warn "CLAUDE.md declares '$declared' as this project's process provider, but it is not"
        warn "  installed for this user. Kinglet's built-in discovery surface (the \`unity-brainstorming\`"
        warn "  skill) is the fallback. Re-run install.sh to refresh the declaration, or delete the"
        warn "  'Process provider' section from CLAUDE.md."
    fi
fi

# ── Summary ──────────────────────────────────────────────────────────────────
printf '\n%s\n' "${BOLD}$PASS_C passed · $WARN_C warning(s) · $FAIL_C failure(s)${NC}"
[ "$FAIL_C" -gt 0 ] && exit 1
exit 0
