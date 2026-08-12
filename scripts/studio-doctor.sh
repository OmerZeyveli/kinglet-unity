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
#   ./scripts/studio-doctor.sh [--project-dir /path/to/UnityProject]
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

usage() { sed -n '3,16p' "$0" | sed 's/^# \{0,1\}//'; exit 0; }

PROJECT_DIR="$(pwd)"
while [ $# -gt 0 ]; do
  case "$1" in
    --project-dir) [ $# -ge 2 ] || { printf 'err: --project-dir requires a path\n' >&2; exit 2; }
                   PROJECT_DIR="$2"; shift 2 ;;
    -h|--help)     usage ;;
    *)             printf 'Unknown argument: %s (use --help)\n' "$1" >&2; exit 2 ;;
  esac
done
PROJECT_DIR="$(cd "$PROJECT_DIR" 2>/dev/null && pwd)" || { printf 'Project directory not found.\n' >&2; exit 2; }
CLAUDE_DIR="$PROJECT_DIR/.claude"
RECEIPT="$CLAUDE_DIR/state/install-receipt.tsv"

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
  UV_VER=$(uv --version 2>/dev/null || true); UV_VER=${UV_VER%%$'\n'*}
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
    SRV=${SRV%%$'\n'*}
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
  # under `modified since install — install.sh will keep your versions`. Half of that is false. The
  # two readers do NOT agree about an unreadable-origin row, because only one of them classifies with
  # a `case`. Measured 2026-08-13 on a fixture whose origin column was mangled to `toolkit ` (trailing
  # space) on a `.claude/rules/*.md` PAYLOAD row — see the report block below for the root-file rows,
  # which the same mangling costs their ownership rather than their contents — with the toolkit's own
  # copy of the file bumped so an overwrite would be visible:
  #
  #   uninstall.sh — a `case` whose `*)` branch keeps. Kept the file, printed `keep 1 file(s) you
  #                  modified`. True whatever the bytes say.
  #   install.sh   — NOT a `case`. `grep -n 'if \[ "$origin" = user-modified \]' install.sh` finds an
  #                  if/else, so an unreadable origin falls straight to the sha test and the BYTES
  #                  decide, not the column:
  #                    bytes still match the recorded sha → the row never enters MODIFIED_FILES, no
  #                      `keeping yours` line is printed, the payload loop OVERWRITES the file, and the
  #                      row is rewritten as a clean `toolkit`;
  #                    bytes drifted → the sha test catches it and the file is kept.
  #
  # So `install.sh will keep your versions` is true of `user-modified` rows and of `toolkit` rows whose
  # bytes drifted, and false for exactly the sub-case above — the one a mangled column most likely
  # produces, since mangling the column does not touch the file. These rows therefore get their own
  # line, which also keeps them out of a MODIFIED count that would then be describing two different
  # futures. Fixing install.sh's asymmetry is a separate change; this file describes install.sh as it
  # is.
  #
  # The sha comparison stays fail-closed the same way uninstall.sh's `sha_of` is: an unreadable file
  # yields the empty string, which never equals a recorded checksum, so the row lands in MODIFIED and
  # is reported rather than silently passed.
  VERIFIED=0; MODIFIED=0; MISSING=0; UNREADABLE=0
  MODIFIED_LIST=""; MISSING_LIST=""; UNREADABLE_LIST=""
  while IFS=$'\t' read -r rel recorded _mode origin; do
    case "$rel" in ''|\#*|path) continue ;; esac
    abs="$PROJECT_DIR/$rel"
    if [ ! -f "$abs" ]; then
      MISSING=$((MISSING + 1)); MISSING_LIST="${MISSING_LIST}${rel}"$'\n'
      continue
    fi
    case "$origin" in
      user-modified)
        MODIFIED=$((MODIFIED + 1)); MODIFIED_LIST="${MODIFIED_LIST}${rel}"$'\n'
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
  fi
  if [ "$UNREADABLE" -gt 0 ]; then
    # Also not a failure, and deliberately not a claim about what happens to the file next. The
    # receipt carries more than one class of row and they do not share an outcome — measured
    # 2026-08-13, three fixtures, each with the toolkit's own copy bumped so an overwrite would show:
    #
    #   .claude/** payload rows      — Step 5's payload loops write them unconditionally unless
    #                                  is_modified says otherwise, so the upgrade scan's sha test
    #                                  decides: bytes unchanged → overwritten, bytes drifted → kept.
    #   MCP-SETUP.md, .mcp.json      — Step 8b/8c write them ONLY when absent (`[ ! -f ]`), so the
    #                                  file is untouched either way. What the column costs there is the
    #                                  ROW: `owned_by_installer`'s `$4 == "toolkit"` test fails on a
    #                                  mangled origin, and MCP-SETUP.md's row was dropped entirely
    #                                  while the identical fixture with a clean origin kept it. The
    #                                  file silently stops being owned, so uninstall.sh stops removing
    #                                  it. (.mcp.json survived the same mangling, because
    #                                  owned_by_installer's reference-copy test matched first — even
    #                                  the two root files do not agree.)
    #
    # The one thing true across all of them is that install.sh's upgrade scan classifies by bytes and
    # not by this column; the consequence depends on the write path. Repairing that asymmetry is
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
  A=$(find "$CLAUDE_DIR/agents" -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
  C=$(find "$CLAUDE_DIR/commands" -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
  S=$(find "$CLAUDE_DIR/skills" -name 'SKILL.md' 2>/dev/null | wc -l | tr -d ' ')
  R=$(find "$CLAUDE_DIR/rules" -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
  printf 'INFO agents=%s commands=%s skills=%s rules=%s\n' "$A" "$C" "$S" "$R"
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
