#!/usr/bin/env bash
# ============================================================================
# test-install-not-done.sh — a run that abandons work says so, and this is what says it did.
#
# `install.sh` exits 0 for every outcome it can report. That is the contract, it is written down in
# MCP-SETUP.md § "What install.sh's exit status means", and it is only safe because a second channel
# carries what the status cannot: the `Not done:` block. Before this file existed,
# `/usr/bin/grep -rn 'Not done' tests/` was EMPTY — the block could be deleted, or every branch but
# one could stop feeding it, with the whole suite green.
#
# TWO ORACLES, AND THEY ARE DELIBERATELY DIFFERENT.
#
#   1. THE RUN'S OWN REPORT. Drive install.sh into a state where it abandons something, read the
#      block. This is the only oracle that can see this class at all: tests/test-install-dryrun.sh
#      says so in its own words — "A RUN THAT WRITES NOTHING IS INVISIBLE TO ALL THREE ORACLES AT
#      ONCE" — because a find snapshot, a receipt diff and a content hash are all quiet on a branch
#      that declined. What was abandoned leaves no trace on the filesystem by construction; the
#      report is the trace.
#
#   2. install.sh'S OWN STRUCTURE, read as text. Section A below never runs the installer. It exists
#      because the invariant it guards is invisible to every filesystem oracle in this suite AND to
#      oracle 1: `$RECEIPT` must still hold the PREVIOUS run's rows at the four `owned_by_installer`
#      call sites, so the receipt may be committed at exactly one point. Move that write earlier and
#      every state in tests/test-install-ownership.sh still passes — the file is written, the rows
#      are right — while four ownership decisions silently start reading THIS run's receipt.
#
# WHY BOTH LIVE IN ONE FILE. The exit contract is one sentence: *exit 0 means the run reached its end
# and reported what it did — the payload is on disk, the receipt lists it, and anything not done is
# in the block.* Section B guards the second half of that sentence. Section A guards the first: the
# receipt exists, and it lists what was actually written rather than what a run intended to write.
# Splitting them would leave one clause of one contract in each of two files.
#
# WHAT THIS FILE CANNOT SEE
#   * THE ABORT SITE. Answering *2* at the "existing .claude/ prompt" is the most complete
#     abandonment install.sh has — nothing is installed, no receipt is written, exit 0 — and it now
#     emits the block. It is unreachable from here: the prompt is skipped entirely unless stdin is a
#     tty (`[ "$ASSUME_YES" -eq 1 ] || [ ! -t 0 ]` takes the non-interactive branch), so reaching it
#     needs a pty. Measured by hand 2026-08-14 with `script -q -e -c ... /dev/null`: the block prints,
#     rc=0, and `.claude/` holds only the pre-existing foreign file. `script` is not used here —
#     BSD's takes a different argument shape, and this suite is kept portable to macOS.
#   * WHETHER THE PROSE IS TRUE. Each assertion below matches a needle from one entry, which proves
#     the site reaches the block and not that the sentence after it describes the world. The
#     consequence clauses ("they will never fire", "no MCP server to reach") are reasoned, not
#     measured — tests/test-install-ownership.sh is where a claim about what is on disk gets checked.
#   * THE FOUR WAYS `CLAUDE_MD_BRANCH=skipped` IS REACHED. One entry covers all four, so a fixture
#     here proves one of them and the other three are covered by the shared recording point rather
#     than by measurement. Only the generator-failure arm is exercised; the absent-generator arm was
#     measured by hand on a scratch toolkit.
#   * ANYTHING ABOUT ORDER WITHIN THE BLOCK. Entries appear in the order the sites are reached, which
#     is install.sh's line order and not a promise.
# ============================================================================
# Self-contained: own set -euo pipefail, own pass/fail, REPO from BASH_SOURCE. The runner's assert_*
# helpers are deliberately not used — the runner does `set +e` before sourcing, so an undefined
# helper prints to stderr and contributes no failure token, and this file would report green on the
# defect it exists to catch.
set -euo pipefail

# ${BASH_SOURCE[0]}, not $0: the runner does `( source "$test_file" )`, and inside a sourced file $0
# is the *sourcing* shell's $0.
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAILURES=0

fail() { printf 'FAIL: %s\n' "$1"; FAILURES=$((FAILURES + 1)); }
pass() { printf 'PASS: %s\n' "$1"; }

SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT

INSTALLER="$REPO/install.sh"

# ============================================================================
# SECTION A — the receipt is committed at exactly one point, and that point is write_receipt
# ============================================================================
# The invariant, in install.sh's own words: "$RECEIPT still holds the PREVIOUS run's receipt at every
# call site below." Four `owned_by_installer` calls depend on it — the orphan routing, the payload
# loop, the .mcp.json row and the MCP-SETUP.md row — and every one of them asks "was this file ours
# BEFORE this run?" A receipt written earlier answers that question with this run's own rows, and
# every answer becomes yes.
#
# THIS READS TEXT, NOT BEHAVIOUR, and that is the point rather than a shortcut. No fixture can
# distinguish "the receipt was written at the end" from "the receipt was written early and happens to
# contain the same rows" — the file on disk is identical either way. The write's POSITION is the
# invariant, so the source is the only place it is visible.
#
# `[ -s "$RECEIPT_TMP" ]` inside write_receipt is not checked here. It is load-bearing for a
# different reason (MODE=foreign is defined by the receipt's ABSENCE, so an unconditional write would
# destroy that mode), and its oracle is a fixture rather than the source.

# receipt_write_report <file> — prints `fn=<0|1> inside=<n> outside=<n> unclassified=<n>`,
# with ` lines=<n,n,…>` appended whenever `outside` or `unclassified` is non-zero, so a red names the
# logical lines that caused it instead of leaving the reader to find them.
#
#   fn            1 if a `write_receipt() {` opening and a column-0 `}` closing were both found.
#                 Guards the whole check against going vacuous after a rename or a re-indent.
#   inside        writes to $RECEIPT inside write_receipt's body.
#   outside       writes to $RECEIPT anywhere else. This is the invariant.
#   unclassified  references to $RECEIPT that are neither a recognised write nor a recognised read.
#                 Fail-closed: an unrecognised shape is a red, not a shrug.
#
# THE FIRST VERSION OF THIS COUNTED ONE SPELLING — `> "$RECEIPT"` — AND THE REVIEWER BROKE IT SIX
# WAYS IN A ROW. `> "${RECEIPT}"`, `> $RECEIPT`, `| tee "$RECEIPT"`, `cp /dev/null "$RECEIPT"`,
# `mv "$RECEIPT_TMP" "$RECEIPT"` and `>| "$RECEIPT"` each added a second commit point outside the
# function with the check still reporting clean, and the whole file still printing green. The one
# that mattered was `cp "$RECEIPT_TMP" "$RECEIPT"` before the `write_receipt` call: behaviour
# unchanged, invariant destroyed, suite green. `mv "$RECEIPT_TMP" "$RECEIPT"` is the single most
# natural idiom for committing a temp file, so this was not a contrived evasion — it is the shape
# the next owner reaches for first.
#
# THE SECOND VERSION CLASSIFIED PHYSICAL LINES, AND A BACKSLASH BROKE IT:
#
#     mv "$RECEIPT_TMP" \
#        "$RECEIPT"
#
# reported clean. The first physical line names only $RECEIPT_TMP, which the reference pattern
# correctly excludes; the second is `   "$RECEIPT"`, which trips the trailing-token read rule. That
# bypass was OUTSIDE the limit this header stated — the verb IS listed and the temp IS named — and
# it is not hypothetical: install.sh carries 25 non-comment continuation lines, and one of them
# already splits a command whose argument list contains "$RECEIPT". **So continuations are folded
# into one logical line BEFORE anything is classified.** Extending the stated limit instead was
# rejected: the honesty of that limit is what makes this guard worth trusting, and a second entry in
# it starts to read as a list of things the guard does not do.
#
# WRITES ARE DETECTED THREE WAYS, AND THE THIRD IS THE VERB-INDEPENDENT ONE:
#
#   1. Any output redirection whose target is the reference — `>`, `>>`, `>|`, `N>`, `exec N>` —
#      quoted, braced or bare.
#   2. A mutating command word on the logical line. A spelling list, and therefore the weak one.
#   3. ANY LOGICAL LINE NAMING BOTH $RECEIPT_TMP AND $RECEIPT. That is what committing a temp file
#      IS, whatever verb does it, and it catches `mv`, `cp`, `install`, `tee`, `rsync` and a command
#      held in a variable with one rule and no list. install.sh's own commit does NOT trip it:
#      `sort … "$RECEIPT_TMP"` and `} > "$RECEIPT"` are separate logical lines.
#
#      RULE 3 SHORT-CIRCUITS, AND THAT MISDIAGNOSES ONE SHAPE. A line that only READS both — a
#      `diff "$RECEIPT_TMP" "$RECEIPT"`, or a log line naming the pair — is counted as a write before
#      the read tests run, so A.1 reds and blames the ownership invariant for a diff. The direction is
#      safe (fail-closed and loud) and the `lines=` field points straight at it; if that is what you
#      are looking at, this paragraph is the answer, and rule 3 is still worth its cost.
#
# READS ARE RECOGNISED NARROWLY: a file-test operator, a reader command word, an input redirection,
# or the reference as the logical line's final token. Everything else is `unclassified` and reds —
# which is how a write through an interpreter (`python3 -c "open('$RECEIPT','w')"`) is caught without
# naming python, and where `[ -n "$RECEIPT" ]` and `jq . "$RECEIPT"` land too.
#
# THE STATED LIMIT, because a guard's blind spot belongs beside it: rule 4's trailing-token
# concession exists for one real line — the closing line of a multi-line awk program, where the
# reference is a bare file argument with no command word in sight. A mutating command that (a) is
# spelled in no list, (b) does not mention $RECEIPT_TMP, and (c) takes $RECEIPT as its last argument
# would pass. `$SOME_CMD /dev/null "$RECEIPT"` is that shape; it is measured and reported, not
# claimed away. It is the ONLY entry in this limit, and folding is what keeps it that way.
#
# `[$]RECEIPT`, not `\$RECEIPT`: a backslash-dollar inside an awk ERE is an escape whose meaning is
# not portable, and a bracket expression says the same thing in every awk. The reference pattern
# requires a non-identifier character after RECEIPT so `$RECEIPT_TMP`, `$RECEIPT_REL`,
# `$RECEIPT_ROWS` and `$RECEIPT_WRITTEN` are not mistaken for it.
receipt_write_report() {
  awk '
    function classify(L, ln, inside,    w, r, i) {
      if (L !~ refw) return
      if (L ~ /^[[:space:]]*RECEIPT=/) return
      w = 0
      if (L ~ ("[0-9]*>>?\\|?[[:space:]]*" ref)) w = 1
      for (i in wv) if (L ~ ("(^|[^A-Za-z0-9_./-])" wv[i] "([^A-Za-z0-9_./-]|$)")) w = 1
      if (L ~ /[$]\{?RECEIPT_TMP\}?([^A-Za-z0-9_]|$)/) w = 1
      if (w) {
        if (inside) { ins++ } else { out++; where = where (where == "" ? "" : ",") ln }
        return
      }
      r = 0
      if (L ~ /\[[[:space:]]+-[fsehr][[:space:]]/) r = 1
      for (i in rv) if (L ~ ("(^|[^A-Za-z0-9_./-])" rv[i] "([^A-Za-z0-9_./-]|$)")) r = 1
      if (L ~ ("<[[:space:]]*" ref)) r = 1
      if (L ~ (ref "[[:space:]]*$")) r = 1
      if (!r) { unc++; where = where (where == "" ? "" : ",") ln }
    }
    BEGIN {
      ref  = "\"?[$]\\{?RECEIPT\\}?\"?"
      refw = "[$]\\{?RECEIPT\\}?([^A-Za-z0-9_]|$)"
      split("cp mv ln install dd truncate touch shred rsync tee sponge", wv, " ")
      split("grep awk sed cat wc sort comm cut tail head sha256sum stat dirname basename test", rv, " ")
      buf = ""; bufline = 0
    }
    /^[[:space:]]*#/ { next }
    /^write_receipt\(\)[[:space:]]*\{/ { infn = 1; opened = 1 }
    infn && /^\}[[:space:]]*$/ { infn = 0; closed = 1 }
    {
      seg = $0
      cont = (seg ~ /\\$/)
      sub(/[[:space:]]*\\$/, "", seg)
      if (buf == "") { buf = seg; bufline = NR } else { buf = buf " " seg }
      if (cont) next
      classify(buf, bufline, infn)
      buf = ""
    }
    END {
      # A file whose last line is a continuation never reaches the flush above.
      if (buf != "") classify(buf, bufline, infn)
      printf "fn=%d inside=%d outside=%d unclassified=%d", \
        (opened && closed) ? 1 : 0, ins + 0, out + 0, unc + 0
      if (where != "") printf " lines=%s", where
      printf "\n"
    }
  ' "$1"
}

A_GOOD="fn=1 inside=1 outside=0 unclassified=0"
A_REPORT="$(receipt_write_report "$INSTALLER")"
if [ "$A_REPORT" = "$A_GOOD" ]; then
  pass "A.1: install.sh writes the receipt at exactly one point, inside write_receipt"
else
  fail "A.1: install.sh's receipt write points are not what the ownership invariant requires — expected '$A_GOOD', got '$A_REPORT'. Four owned_by_installer call sites read \$RECEIPT expecting the PREVIOUS run's rows"
fi

# ── A.2: one mutant per row of the table below, each a second commit point ──
# A guard that has never been shown to redden is a guard that has been read, not tested — and the
# first version of this one passed half the table, while the second passed the two continuation rows.
# Every mutant is applied to a COPY in $SCRATCH; nothing here touches the repository's install.sh.
# The insertion point is the line immediately before the real commit, which is where a second one
# would most plausibly be added.
#
# NO COUNT IS WRITTEN IN THIS HEADING, and that is not fastidiousness. The round that stripped every
# stale site-count out of install.sh wrote `eleven mutants` here in the same commit, and the table
# was twelve rows before the ink dried. Derive it:
#
#   sed -n '/^done <<MUTANTS$/,/^MUTANTS$/p' tests/test-install-not-done.sh | grep -c "$(printf '\t')"
#
# The table is `name<TAB>shell line`. A tab, because every line here carries quotes and spaces. A
# literal `\n` in the second field becomes a real newline, which is how the continuation rows inject
# a two-physical-line command.
A_MUT_ANCHOR='write_receipt || die'
a_mutant_report() {
  local nm="$1"
  local injected="$2"
  local dst="$SCRATCH/mutant-$nm.sh"
  python3 - "$INSTALLER" "$dst" "$injected" "$A_MUT_ANCHOR" <<'PY'
import sys
src, dst, injected, anchor = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
s = open(src).read()
assert s.count(anchor) == 1, 'the write_receipt call site is not unique'
open(dst, 'w').write(s.replace(anchor, injected.replace('\\n', '\n') + '\n' + anchor, 1))
PY
  receipt_write_report "$dst"
}

while IFS=$'\t' read -r a_name a_line; do
  [ -n "$a_name" ] || continue
  A_M="$(a_mutant_report "$a_name" "$a_line")"
  if [ "$A_M" = "$A_GOOD" ]; then
    fail "A.2/$a_name: a copy of install.sh carrying a second receipt commit point ($a_line) still reported '$A_M' — A.1 cannot see the defect it exists to catch"
  else
    pass "A.2/$a_name: a second commit point spelled '$a_line' reddens the check (reported '$A_M')"
  fi
done <<MUTANTS
redirect-quoted	printf "" > "\$RECEIPT"
redirect-braced	printf "" > "\${RECEIPT}"
redirect-bare	printf "" > \$RECEIPT
redirect-clobber	printf "" >| "\$RECEIPT"
redirect-append	printf "x" >> "\$RECEIPT"
exec-fd	exec 9> "\$RECEIPT"
tee	cat "\$RECEIPT_TMP" | tee "\$RECEIPT" >/dev/null
cp-devnull	cp /dev/null "\$RECEIPT"
cp-tmp	cp "\$RECEIPT_TMP" "\$RECEIPT"
mv-tmp	mv "\$RECEIPT_TMP" "\$RECEIPT"
install-tmp	install -m 644 "\$RECEIPT_TMP" "\$RECEIPT"
python-open	python3 -c "open('\$RECEIPT','w')"
mv-continued	mv "\$RECEIPT_TMP" \\\n   "\$RECEIPT"
cp-continued	cp "\$RECEIPT_TMP" \\\n   "\$RECEIPT"
redirect-continued	printf "" \\\n  > "\$RECEIPT"
MUTANTS

# ── A.3: the commit point moved OUT of write_receipt ────────────────────────
# The other direction, and it is not covered by A.2: here the count of writes is still one. A check
# that only counted would stay green on it.
A_MUT_OUT="$SCRATCH/install-commit-moved.sh"
python3 - "$INSTALLER" "$A_MUT_OUT" <<'PY'
import sys
src, dst = sys.argv[1], sys.argv[2]
s = open(src).read()
inside = '  } > "$RECEIPT" || return 1\n'
assert s.count(inside) == 1, 'the in-function redirection is not where the mutant expects it'
call = 'write_receipt || die'
assert s.count(call) == 1, 'write_receipt call site is not unique'
s = s.replace(inside, '  } > "$RECEIPT_TMP.out" || return 1\n', 1)
s = s.replace(call, 'cat "$RECEIPT_TMP.out" > "$RECEIPT"\nwrite_receipt || die', 1)
open(dst, 'w').write(s)
PY
A_REPORT_OUT="$(receipt_write_report "$A_MUT_OUT")"
if [ "$A_REPORT_OUT" = "$A_GOOD" ]; then
  fail "A.3: a copy of install.sh whose only receipt write was moved OUT of write_receipt still reported '$A_REPORT_OUT' — A.1 counts the writes but does not locate them"
else
  pass "A.3: moving the receipt write out of write_receipt reddens the check (reported '$A_REPORT_OUT')"
fi

# ── A.3b: the abort path reports before it exits ────────────────────────────
# Answering *2* at the existing-.claude/ prompt is the most complete abandonment install.sh has:
# nothing installed, no receipt, exit 0. It is the one recording point no fixture can reach — the
# prompt is skipped entirely unless stdin is a tty — so it is asserted the way Section A asserts
# everything else, in the source. `awk` walks the `case` arm from `*)` to its `;;` and requires both
# halves: recording the abandonment, and printing the block before exiting.
#
# This is a weaker oracle than a run and it is named as one: it proves the calls are on that path,
# not that their output is right. The behaviour was measured by hand with
# `printf '2\n' | script -q -e -c "bash install.sh --project-dir P" /dev/null` — block printed,
# rc=0, .claude/ holding only the pre-existing foreign file.
A_ABORT="$(awk '
  /REPLY_CHOICE:-2/            { incase = 1 }
  incase && /^[[:space:]]*\*\)/ { inarm = 1 }
  inarm && /note_not_done/     { n = 1 }
  inarm && /print_not_done/    { p = 1 }
  inarm && /exit 0/            { if (n && p) ok = 1; inarm = 0; incase = 0 }
  END { print ok + 0 }
' "$INSTALLER")"
if [ "$A_ABORT" = "1" ]; then
  pass "A.3b: the abort arm records the abandonment and prints the block before its exit 0"
else
  fail "A.3b: the abort arm reaches 'exit 0' without both a note_not_done and a print_not_done before it — a run that installs nothing would exit 0 saying one word"
fi

# ── A.4: one writer for the block itself ────────────────────────────────────
# Every abandonment site records into $NOT_DONE and one function prints it. A second printer is how the block
# and its contract drift apart — one of them would be reachable on a path the contract does not
# describe. Comments are excluded, so the reasoning above `print_not_done` does not count as a
# second writer.
A_PRINTERS="$(awk '
  /^[[:space:]]*#/ { next }
  /Not done:/ { n++ }
  END { print n + 0 }
' "$INSTALLER")"
if [ "$A_PRINTERS" = "1" ]; then
  pass "A.4: exactly one line of install.sh prints the block header, so there is one writer"
else
  fail "A.4: install.sh has $A_PRINTERS non-comment lines carrying the block header — the contract in MCP-SETUP.md describes one block from one writer"
fi

# ============================================================================
# SECTION B — the block, on runs that abandon work
# ============================================================================
# KINGLET_USER_SETTINGS is pointed at a path that does not exist so the Superpowers provider
# detection takes the same branch on every machine. stdin is /dev/null so no `read -rp` can block.
INSTALL_OUT=""
run_install() {
  local dir="$1"
  local label="$2"
  shift 2
  local rc=0
  INSTALL_OUT="$(KINGLET_USER_SETTINGS="$SCRATCH/absent-user-settings.json" \
    bash "$INSTALLER" --project-dir "$dir" --yes "$@" 2>&1 </dev/null)" || rc=$?
  if [ "$rc" -eq 0 ]; then
    pass "$label: install.sh exited 0, which is the contract's own claim about every reportable outcome"
  else
    fail "$label: install.sh exited $rc — the block assertions below describe a run that did not reach its summary"
  fi
}

# `--variant` is passed explicitly rather than defaulted: the shape of the project decides which
# branch install.sh takes, and a fixture whose variant is implicit is a fixture whose relevance is
# implicit. Nothing here writes the file it is about to look for.
new_fixture() {
  local name="$1"
  local variant="$2"
  local dir
  dir="$SCRATCH/$name"
  bash "$REPO/tests/fixtures/mkproject.sh" "$dir" --variant "$variant" >/dev/null
  printf '%s' "$dir"
}

# The block, from its header to the `Next steps:` list that follows it. Extracted rather than
# grepped so that an assertion cannot be satisfied by a warn line elsewhere in the run carrying
# similar words — several of them do, deliberately, since each site warns AND records.
not_done_block() {
  awk '/^Not done:/ { f = 1 } f && /^Next steps:/ { f = 0 } f' <<< "$INSTALL_OUT"
}

# assert_entry <label> <needle> — the block exists and one of its entries carries the needle.
# `grep -qF` on a here-string, never on a pipe: grep -q exits the instant it matches without
# draining stdin, and under `set -o pipefail` the writer's SIGPIPE becomes a failure.
assert_entry() {
  local label="$1"
  local needle="$2"
  local block
  block="$(not_done_block)"
  if [ -z "$block" ]; then
    fail "$label: the run printed no block at all, so the site did not record — it may still have warned, which is the exact half-measure this file exists to catch"
    return 0
  fi
  if grep -qF -- "$needle" <<< "$block"; then
    pass "$label: the block names it"
  else
    fail "$label: the block was printed but carries no entry matching '$needle' — some other site recorded and this one did not"
  fi
}

# ── B.0: the control. A clean install abandons nothing and says nothing ─────
# Without this, every assertion below is satisfied by an installer that prints the block
# unconditionally — and an unconditional block is worse than none: it makes "no block means nothing
# was abandoned", the sentence MCP-SETUP.md sells to callers, false on every run.
B0="$(new_fixture clean-install urp)"
run_install "$B0" "B.0 (clean install)"
if [ -n "$(not_done_block)" ]; then
  fail "B.0: a clean install printed the block — the contract's 'no block means nothing was abandoned' is then meaningless, and every assertion below passes vacuously"
else
  pass "B.0: a clean install prints no block"
fi
# The contract has to reach the project, not only the repository. R3's whole ground for putting it in
# MCP-SETUP.md is that this is the file install.sh copies to the project root.
if [ -f "$B0/MCP-SETUP.md" ] && grep -qF -- 'No `Not done:` block on an exit-0 run means nothing was abandoned' "$B0/MCP-SETUP.md"; then
  pass "B.0: the installed project's MCP-SETUP.md carries the exit contract"
else
  fail "B.0: the exit contract did not reach $B0/MCP-SETUP.md — a contract that only exists in the toolkit repository is not one a user of an installed project can read"
fi

# ── B.0b: --dry-run, the contract's one stated exit-0 exception ─────────────
# MCP-SETUP.md says "One exit-0 run is not an install and prints no block: --dry-run". That sentence
# had no assertion, in the file whose whole subject is that an unasserted sentence about install.sh
# is a sentence that can go false. The fixture is deliberately one that WOULD produce a block on a
# real run — a bare project with a flag it cannot honour — so this cannot pass by having nothing to
# report. Step 4's unreadable-origin scan can call note_not_done before the dry-run exit, and the
# dry run is supposed to print it nowhere; this is the arm that says so.
B0B="$(new_fixture dryrun-exception bare)"
run_install "$B0B" "B.0b (--dry-run against a project a real run would report on)" --dry-run --with-mcp
if [ -n "$(not_done_block)" ]; then
  fail "B.0b: --dry-run printed the block — MCP-SETUP.md tells callers it does not, and a dry run abandons nothing because it attempts nothing"
else
  pass "B.0b: --dry-run prints no block, as the shipped contract states"
fi
if grep -qF -- 'Dry run complete — nothing written.' <<< "$INSTALL_OUT"; then
  pass "B.0b: the dry run ended with the line the contract names in its place"
else
  fail "B.0b: the dry run did not end with 'Dry run complete — nothing written.' — the contract offers that line as what a caller reads instead of the block"
fi

# ── B.1: a --with-* flag against a project with no Packages/manifest.json ───
# The plan's first reproduction. Both flags are passed, because one manifest-shaped failure abandons
# every flag the run carried and a single-flag fixture cannot tell "recorded once" from "recorded for
# the flag that happened to run first".
B1="$(new_fixture no-manifest bare)"
run_install "$B1" "B.1 (--with-* against a bare project)" --with-mcp --with-input-system
assert_entry "B.1 (--with-mcp)"          '--with-mcp — skipped: this project has no Packages/manifest.json'
assert_entry "B.1 (--with-input-system)" '--with-input-system — skipped: this project has no Packages/manifest.json'

# ── B.2: a manifest the surgical insert cannot edit ─────────────────────────
# The plan's second reproduction. A manifest with no "dependencies" key matches nothing, the failure
# arm restores the original, and the run ends with the file byte-identical and the flag gone. The
# fixture's own manifest is REPLACED rather than appended to — a `printf >>` that creates the shape it
# then measures is how a probe certifies itself.
B2="$(new_fixture unusable-manifest urp)"
printf '{\n  "testables": [],\n  "enableLockFile": true\n}\n' > "$B2/Packages/manifest.json"
run_install "$B2" "B.2 (manifest with no dependencies key)" --with-mcp
assert_entry "B.2" '--with-mcp — the manifest could not be edited safely'

# ── B.3: a .mcp.json that is not ours ──────────────────────────────────────
# The installer will not merge someone's JSON, correctly. What it leaves behind is a project whose
# unity-* agents hold mcp__UnityMCP__* tools with no server to resolve them.
B3="$(new_fixture foreign-mcp-json urp)"
printf '{\n  "mcpServers": {\n    "somethingelse": {\n      "type": "http",\n      "url": "http://localhost:9999/mcp"\n    }\n  }\n}\n' > "$B3/.mcp.json"
run_install "$B3" "B.3 (.mcp.json without a UnityMCP entry)"
assert_entry "B.3" '.mcp.json — yours has no UnityMCP entry and was not rewritten'

# ── B.4: a CLAUDE.md.generated the installer will not overwrite ─────────────
# The one abandonment that already had a summary line of its own — Next steps item 2 — and still no
# block entry. Both are correct: a reader looks in one place or the other.
B4="$(new_fixture foreign-generated urp)"
printf '# My own CLAUDE.md\n\nNothing generated here.\n' > "$B4/CLAUDE.md"
printf '# My own CLAUDE.md.generated\n\nDo not overwrite this.\n' > "$B4/CLAUDE.md.generated"
run_install "$B4" "B.4 (CLAUDE.md.generated is the user's)"
assert_entry "B.4" 'CLAUDE.md.generated — yours was kept untouched'

# ── B.4b: a CLAUDE.md of the user's own, with no generated markers ─────────
# THE HOLE THE FIRST ROUND SHIPPED. This branch WRITES CLAUDE.md.generated and was excluded from the
# block on the ground that "work done differently is not work abandoned" — a criterion invented to
# escape the stated one. Claude Code reads CLAUDE.md; the toolkit's configuration sits in the file
# beside it, inert, exactly as an unregistered hook sits on disk. Measured before the fix: rc=0, no
# block, and zero `kinglet:generated` markers in the CLAUDE.md that Claude Code will read. Every
# project that already has a CLAUDE.md takes this branch.
#
# The two halves are asserted separately: that the branch really ran (the beside-file exists and the
# user's own file was not touched), and that the block names it. Without the first, a fixture that
# quietly took the `refreshed` or `new` branch would leave the second asserting nothing.
B4B="$(new_fixture markerless-claude-md urp)"
printf '# My Game\n\nMy own notes. No generated markers anywhere in this file.\n' > "$B4B/CLAUDE.md"
B4B_SHA="$(sha256sum "$B4B/CLAUDE.md" | cut -d' ' -f1)"
run_install "$B4B" "B.4b (the user's CLAUDE.md has no markers)"
if [ -f "$B4B/CLAUDE.md.generated" ] && [ "$(sha256sum "$B4B/CLAUDE.md" | cut -d' ' -f1)" = "$B4B_SHA" ]; then
  pass "B.4b: the run wrote CLAUDE.md.generated beside the user's untouched CLAUDE.md, so the branch ran"
else
  fail "B.4b: the run did not take the beside-yours branch, so the entry assertion below is about a branch that did not run"
fi
if grep -qF -- 'kinglet:generated' "$B4B/CLAUDE.md"; then
  fail "B.4b: the user's CLAUDE.md gained generated markers — this fixture is no longer the state the entry describes"
else
  pass "B.4b: the file Claude Code reads carries none of the generated block, which is what makes this an abandonment"
fi
assert_entry "B.4b" 'CLAUDE.md — yours has no generated markers'

# ── B.5: an upgrade whose kept settings.json leaves a hook unregistered ─────
# Two installs, because this is an UPGRADE-shaped defect and no fresh install can reach it: the file
# must be ours first, then edited, before the second run keeps it. The edit renames one registration
# so the hook ships, lands on disk, and is registered nowhere.
B5="$(new_fixture kept-settings urp)"
run_install "$B5" "B.5 install 1"
python3 - "$B5/.claude/settings.json" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
assert '.claude/hooks/' in s, 'the payload settings.json registers no hooks — this fixture proves nothing'
i = s.index('.claude/hooks/')
j = s.index('.sh', i) + len('.sh')
open(p, 'w').write(s[:i] + '.claude/hooks/not-a-real-hook.sh' + s[j:])
PY
run_install "$B5" "B.5 install 2 (settings.json kept)"
assert_entry "B.5" 'installed but NOT registered'

# ── B.6: gitignore_plan's fallback, reached by mutation ─────────────────────
# THE THIRD REPRODUCTION IN THE PLAN, AND IT IS UNREACHABLE AS WRITTEN. Every path through
# gitignore_plan returns one of `covered`, `present` or `append` and exits 0; the `*)` arm exists
# because install.sh captures the status rather than depending on it, and no fixture can produce an
# unusable verdict. Mutation is the only way in, and the mutant is the smallest one that reaches the
# arm: a first line of output that is none of the three verdicts.
#
# IT IS ALSO NOT A FLAG ABANDONMENT. This run passes no --with-* flag at all — the fallback fires on
# an ordinary install, which is what makes the consequence worth naming: .claude/settings.local.json
# and .claude/state/* are then not ignored, in a project the user is about to commit.
#
# A SCRATCH TOOLKIT, NOT AN EDIT IN PLACE. install.sh derives SCRIPT_DIR from its own location, so
# the copy needs the payload beside it; `cp -R` of .claude/ and scripts/ is the shape
# tests/test-install-ownership.sh state B2 already uses for a scratch toolkit.
B6_TK="$SCRATCH/toolkit-gitignore-fallback"
mkdir -p "$B6_TK"
cp -R "$REPO/.claude" "$B6_TK/.claude"
cp -R "$REPO/scripts" "$B6_TK/scripts"
cp "$REPO/MCP-SETUP.md" "$B6_TK/MCP-SETUP.md"
python3 - "$INSTALLER" "$B6_TK/install.sh" <<'PY'
import sys
src, dst = sys.argv[1], sys.argv[2]
s = open(src).read()
anchor = 'gitignore_plan() {\n'
assert s.count(anchor) == 1, 'gitignore_plan is not where the mutant expects it'
inject = '  printf \'%s\\n\' "mutant-verdict"; return 0\n'
open(dst, 'w').write(s.replace(anchor, anchor + inject, 1))
PY
B6="$(new_fixture gitignore-fallback urp)"
B6_RC=0
INSTALL_OUT="$(KINGLET_USER_SETTINGS="$SCRATCH/absent-user-settings.json" \
  bash "$B6_TK/install.sh" --project-dir "$B6" --yes 2>&1 </dev/null)" || B6_RC=$?
if [ "$B6_RC" -eq 0 ]; then
  pass "B.6: the mutated installer still exited 0 — the fallback is a warning and a skipped file, not a dead run"
else
  fail "B.6: the mutated installer exited $B6_RC — the fallback is supposed to let the install continue"
fi
# The sanity check the mutant needs. Without it a mutation that stopped reaching the arm would leave
# B.6 asserting nothing while reporting a clean pass.
if grep -qF -- 'gitignore_plan gave an unusable verdict (mutant-verdict)' <<< "$INSTALL_OUT"; then
  pass "B.6: the mutant reached the fallback arm"
else
  fail "B.6: the mutant never reached the fallback arm — the entry assertion below is about a branch that did not run"
fi
assert_entry "B.6" '.gitignore — its plan could not be computed'
# The consequence, not just the decline. The plan's own note on this site is that the fallback did
# not name what it costs, and the entry lists the entries from $GITIGNORE_ENTRIES so it cannot drift
# from the set Step 7 would have appended.
assert_entry "B.6 (consequence)" '.claude/settings.local.json'

# ── B.7: a Packages/manifest.json.bak that is not ours ─────────────────────
# The site that ALREADY reached the block before this file existed — it is `MANIFEST_DECLINED`'s old
# job, now one entry among many. Covered here for the same reason the mechanism was generalised
# rather than copied: the one site that worked is the one a refactor is likeliest to break silently.
B7="$(new_fixture foreign-manifest-bak urp)"
printf '{ "notes": "my own pre-edit backup", "dependencies": {} }\n' > "$B7/Packages/manifest.json.bak"
run_install "$B7" "B.7 (a manifest backup that is the user's)" --with-mcp
assert_entry "B.7" '--with-mcp — declined: Packages/manifest.json.bak is not ours to overwrite'

# ── B.8: a receipt row whose origin column cannot be read ──────────────────
# One of the two keeps that DO belong in the block, and the discriminator is that nobody chose
# anything: the row is corrupt, so the file on disk may be this version's copy or a stale one and the
# run cannot say which. Hand-edited, deliberately — the state is reached by corruption or by a future
# version writing an origin value this one does not know, and neither is producible from a fixture.
# tests/test-install-ownership.sh's origin-column states edit the same column the same way.
B8="$(new_fixture unreadable-origin urp)"
run_install "$B8" "B.8 install 1"
python3 - "$B8/.claude/state/install-receipt.tsv" <<'PY'
import sys
p = sys.argv[1]
rows = open(p).readlines()
hit = False
for i, line in enumerate(rows):
    f = line.rstrip('\n').split('\t')
    if len(f) == 4 and f[0].startswith('.claude/rules/'):
        f[3] = 'origin-from-a-later-version'
        rows[i] = '\t'.join(f) + '\n'
        hit = True
        break
assert hit, 'no .claude/rules/ row to corrupt — this fixture proves nothing'
open(p, 'w').writelines(rows)
PY
run_install "$B8" "B.8 install 2 (the origin column is unreadable)"
assert_entry "B.8" 'were NOT replaced with this version'

# ── B.9: a surface this payload no longer ships, with the user's edits on it ─
# THE ABANDONED WORK IS THE REMOVAL, NOT THE FILE, which is why it is in the block while the
# `keeping yours:` list is not. Built as a real upgrade — a scratch toolkit that ships one extra
# agent, then the current one, which no longer does — rather than by writing a receipt row for a path
# by hand. A hand-written row would test the orphan scan against input no version of this toolkit
# produces; a payload that shrank is the actual event, and it is what the 2026-08-03 cut was.
B9_TK="$SCRATCH/toolkit-with-extra-agent"
mkdir -p "$B9_TK"
cp -R "$REPO/.claude" "$B9_TK/.claude"
cp -R "$REPO/scripts" "$B9_TK/scripts"
cp "$REPO/MCP-SETUP.md" "$B9_TK/MCP-SETUP.md"
cp "$INSTALLER" "$B9_TK/install.sh"
printf -- '---\nname: unity-retired\ndescription: An agent the next version drops.\nmodel: sonnet\ncolor: gray\ntools: Read\n---\n\nRetired.\n' \
  > "$B9_TK/.claude/agents/unity-retired.md"
B9="$(new_fixture shrinking-payload urp)"
B9_RC=0
KINGLET_USER_SETTINGS="$SCRATCH/absent-user-settings.json" \
  bash "$B9_TK/install.sh" --project-dir "$B9" --yes >/dev/null 2>&1 </dev/null || B9_RC=$?
if [ "$B9_RC" -eq 0 ]; then
  pass "B.9 install 1 (previous version, one extra agent): install.sh exited 0"
else
  fail "B.9 install 1 (previous version, one extra agent): install.sh exited $B9_RC"
fi
if [ -f "$B9/.claude/agents/unity-retired.md" ]; then
  pass "B.9: the previous version installed the agent the current payload drops"
else
  fail "B.9: the extra agent never landed, so install 2 has no orphan to keep and the entry assertion is vacuous"
fi
printf '\nMy own note on this agent.\n' >> "$B9/.claude/agents/unity-retired.md"
run_install "$B9" "B.9 install 2 (current version, payload shrank)"
assert_entry "B.9" 'retired surface(s) listed above were NOT removed'

# ── B.10: the generator does not produce a CLAUDE.md ────────────────────────
# `CLAUDE_MD_BRANCH=skipped` is reached four ways and recorded once. This exercises the fresh-file
# arm; the absent-generator arm was measured by hand on a scratch toolkit with the script deleted,
# and it is the arm that exposed the summary line "see the warning above" printing where no warning
# had been printed — install.sh now warns there, so the entry's own pointer resolves.
B10_TK="$SCRATCH/toolkit-broken-generator"
mkdir -p "$B10_TK"
cp -R "$REPO/.claude" "$B10_TK/.claude"
cp -R "$REPO/scripts" "$B10_TK/scripts"
cp "$REPO/MCP-SETUP.md" "$B10_TK/MCP-SETUP.md"
cp "$INSTALLER" "$B10_TK/install.sh"
printf '#!/usr/bin/env bash\nexit 1\n' > "$B10_TK/scripts/generate-claude-md.sh"
B10="$(new_fixture broken-generator urp)"
B10_RC=0
INSTALL_OUT="$(KINGLET_USER_SETTINGS="$SCRATCH/absent-user-settings.json" \
  bash "$B10_TK/install.sh" --project-dir "$B10" --yes 2>&1 </dev/null)" || B10_RC=$?
if [ "$B10_RC" -eq 0 ]; then
  pass "B.10: a failed generator still exits 0 — the payload landed and the receipt was written"
else
  fail "B.10: install.sh exited $B10_RC when the generator failed — the contract says a reportable outcome is a 0"
fi
if [ -f "$B10/CLAUDE.md" ]; then
  fail "B.10: CLAUDE.md exists, so the generator did not fail and the entry below is about a branch that did not run"
else
  pass "B.10: no CLAUDE.md was produced, which is the state the entry describes"
fi
assert_entry "B.10" 'CLAUDE.md — not generated'

# ── B.11: the block is placed where the contract says it is ────────────────
# MCP-SETUP.md tells a caller the block is "printed immediately before `Next steps:`". A block after
# the numbered list reads as a footnote to it, and a caller that stops reading at `Next steps:` never
# sees it. B.10's output is still in INSTALL_OUT and carries both.
#
# awk, not `grep -n | cut`: grep exits 1 when the needle is absent, `set -o pipefail` promotes that
# through the pipeline, and at an ASSIGNMENT `set -e` kills the file with no message. Measured
# 2026-08-14 while red-first-proving this file against the pre-task installer: that shape took the
# run down at this line, so this assertion printed nothing, the summary printed nothing, and the exit
# status was indistinguishable from an ordinary red. awk exits 0 whether it matched or not, and
# prints 0 for absent — which the comparison below then reads as "not before", correctly.
line_of() {
  awk -v re="$1" '$0 ~ re { print NR; found = 1; exit } END { if (!found) print 0 }' <<< "$INSTALL_OUT"
}
B11_ND="$(line_of '^Not done:')"
B11_NS="$(line_of '^Next steps:')"
if [ "$B11_ND" -gt 0 ] && [ "$B11_NS" -gt 0 ] && [ "$B11_ND" -lt "$B11_NS" ]; then
  pass "B.11: the block precedes the Next steps list, as the shipped contract states"
else
  fail "B.11: the block is not before the Next steps list (block at line '$B11_ND', list at line '$B11_NS') — MCP-SETUP.md tells callers it is printed immediately before it"
fi

# ============================================================================
if [ "$FAILURES" -eq 0 ]; then
  printf '\nAll assertions passed.\n'
else
  printf '\n%s assertion(s) did not hold.\n' "$FAILURES"
  exit 1
fi
