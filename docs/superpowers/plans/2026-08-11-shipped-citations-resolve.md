# Shipped Citations Resolve — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `.claude/skills/subagent-driven-implementation/SKILL.md` (recommended) or `.claude/skills/unity-execution/SKILL.md` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every citation a shipped surface makes resolves in an installed Unity project, and a guard keeps it that way.

**Architecture:** One new self-contained bash test derives the installed payload the same way `install.sh` does, then enforces two rules over every `.md` in `.claude/` — no `§N` section marker, and no backticked token naming a repository file the payload does not carry. Sixteen citation sites are fixed to satisfy it. Four defects the guard cannot see — the installer's dry-run, the fork's threshold, `GETTING-STARTED.md`'s entry point, and the ledger's stale resume block — are fixed alongside.

**Tech Stack:** bash 3.2-compatible shell, Markdown, TSV. `tests/run-tests.sh`, `scripts/check-provenance.sh`, `python3 -m tools.kinglet_build`.

## Global Constraints

- **Spec:** `docs/superpowers/specs/2026-08-11-shipped-citations-resolve-design.md` at commit `99c18a2`. Where this plan and the spec disagree, the spec wins and the disagreement is a bug in this plan — report it rather than resolving it silently.
- **Branch:** `pioneer/process-chain`. Base for this wave: `99c18a2`.
- **Gates, both must pass before any task is reported done:**
  - `bash tests/run-tests.sh` — needs a timeout above **150000 ms**.
  - `bash scripts/check-provenance.sh` — must end `provenance OK`.
- **Strip ANSI before counting suite headers.** The runner colours the `--- test-*.sh ---` header, so `grep -c '^--- test-.*\.sh ---'` on raw output returns **0** on a completely healthy suite — the exact signal of the catastrophe the count exists to detect. Always: `sed $'s/\x1b\\[[0-9;]*m//g'` first, then compare against `ls tests/test-*.sh | wc -l`.
- **This repository is not a Unity project.** No Editor, no MCP bridge, no C#. Every file here is bash, Markdown or TSV.
- **bash 3.2 compatible.** No `declare -A`, no `grep -oP`. A macOS pass is planned.
- **Never pipe into a reader that can exit early** under `set -euo pipefail` — `grep -q` exits on first match without draining stdin, and SIGPIPE + pipefail kills the script on large inputs while passing on small ones. Use a here-string: `grep -qF -- "$needle" <<< "$haystack"`.
- **`[ x = y ] && continue` is a `set -e` trap** when it is the last command in a loop body: the false test makes the whole AND-list exit 1 and kills the script. Write `if [ x = y ]; then continue; fi`.
- **Two test idioms coexist and mixing them fails silently.** A *self-contained* file sets its own `set -euo pipefail` and defines its own helpers — `bash tests/<file>.sh` is a valid way to run it. A *runner-provided* file uses `assert_contains` / `assert_eq` / `$REPO_DIR` from the runner and defines neither; run standalone it **exits 0 having asserted nothing**. `tests/test-shipped-citations.sh` is self-contained. `tests/test-surface-references.sh` is runner-provided — verify changes to it **through the runner**, reading its section, never standalone.
- **Print `PASS:` / `FAIL:`, not `ok:`.** `run-tests.sh` aggregates by grepping each file's output for those tokens; a file printing anything else contributes 0 to the total and is indistinguishable from a file that never ran.
- **Baseline discipline.** `.claude/` content changes trip `tests/kinglet/test_baseline_inventory.py`'s sha256 tripwires. The fix is **commit, regenerate, commit** — the ordering is circular otherwise, because the test reads `git ls-files` while the regenerator reads `git ls-tree`. Entry point is the **package**: `python3 -m tools.kinglet_build baseline-regenerate --anchor HEAD --expect-drift <n> [--expect-added <n>] [--expect-removed <n>]`; `python3 -m tools.kinglet_build.cli` silently no-ops with exit 0. Run `--dry-run` first and **use the tool's numbers, not this plan's estimate** — report a disagreement instead of tuning the flag until it passes. A categorised file counts twice (once in `full_claude_tree`, once in its category). `baseline-regenerate` updates the JSON but **not** `tests/kinglet/test_baseline_inventory.py`'s hand-maintained constants; fold those into the same baseline commit. Put the baseline update in its own commit.
- **Every new tracked file needs a `provenance.tsv` row** — seven tab-separated columns: path, origin, upstream_version, upstream_path, upstream_sha256, status, note. For files originating here: `original	-	-	-	original	<note>`. A file with no row fails the check as an orphan.
- **`grep` is line-oriented and prose is not.** Before asserting a phrase is absent, flatten: a sentence that wraps across two lines cannot be read by any single-line pattern, whatever it contains. This repository has shipped two stale claims for exactly this reason.
- **A needle that passes for the wrong reason is worse than no needle**, and **a red-first step that starts green is worse than no red-first step** — it reads as "the work is already done". Every "run it and watch it fail" step below means *observe the specific failure named*, not merely a non-zero exit.
- **A sentinel must not contain its own needle.** A note or comment that carries the string a guard searches for satisfies that guard by itself.

---

## File Structure

| File | Responsibility | Task |
|---|---|---|
| `tests/test-shipped-citations.sh` | **Create.** The guard: derives the payload, enforces rule 1 (§N) and rule 2 (repo-only paths), asserts its own coverage floors | 1, 2 |
| `.claude/skills/verification-before-completion/SKILL.md` | Modify. Four `§N` markers; three repo-only paths across two rows | 1, 2 |
| `.claude/skills/systematic-debugging/SKILL.md` | Modify. Three `§N` markers, one of which is an empty cell | 1 |
| `.claude/skills/urp-pipeline/SKILL.md` | Modify. One `§N` naming `sourced-incidents.md` | 1 |
| `.claude/rules/pc-console.md` | Modify. Two repo-only paths, one of them an instruction to act | 2 |
| `.claude/NOTICE.md` | Modify. Three repo-only paths; one is fixed by adding a URL | 2 |
| `install.sh` | Modify. `:257` dry-run states what the real run does | 3 |
| `.claude/skills/subagent-driven-implementation/SKILL.md` | Modify. The fork's threshold, one phrase | 4 |
| `tests/test-surface-references.sh` | Modify. Assert the threshold is stated once, identically | 4 |
| `docs/GETTING-STARTED.md` | Modify. `:162` names the chain's entry | 5 |
| `docs/superpowers/plans/2026-08-10-kinglet-process-chain-ledger.md` | Modify. `RESUME HERE` matches its own task table | 5 |
| `provenance.tsv` | Modify. Rows for the new test, this plan, and this wave's ledger | 1 |
| `docs/superpowers/plans/2026-08-11-shipped-citations-resolve-ledger.md` | Create. This wave's execution ledger | 1 |

---

## Task 1: The guard's rule 1, and the eight `§N` sites

**Files:**
- Create: `tests/test-shipped-citations.sh`
- Create: `docs/superpowers/plans/2026-08-11-shipped-citations-resolve-ledger.md`
- Modify: `.claude/skills/verification-before-completion/SKILL.md:41-44`
- Modify: `.claude/skills/systematic-debugging/SKILL.md:38-40`
- Modify: `.claude/skills/urp-pipeline/SKILL.md:363`
- Modify: `provenance.tsv`

**Interfaces:**
- Consumes: nothing.
- Produces: `tests/test-shipped-citations.sh` containing the shell function `payload_paths()` (no arguments; prints one payload-relative path per line, e.g. `.claude/rules/pc-console.md`, `.claude/scripts/studio-doctor.sh`) and the variable `PAYLOAD` holding its output. Task 2 extends this same file and reuses both.

- [ ] **Step 1: Write the guard with rule 1 only**

Create `tests/test-shipped-citations.sh`:

```bash
#!/usr/bin/env bash
# Self-contained: defines its own helpers, safe to run standalone.
#
# A surface that ships into a user's Unity project can only cite what that user has. Eight citations
# in four shipped skills once pointed at `sourced-incidents.md` — a document that was never deleted
# because it never existed — and seven paths named files install.sh does not copy, one of them a
# rule instructing the reader to inspect a test and report a regression.
set -euo pipefail

# ${BASH_SOURCE[0]}, not $0: the runner does `( source "$test_file" )`, and inside a sourced file $0
# is the *sourcing* shell's $0.
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAILURES=0

# PASS/FAIL, not ok/FAIL: run-tests.sh aggregates by grepping each file's output for those tokens.
fail() { printf 'FAIL: %s\n' "$1"; FAILURES=$((FAILURES + 1)); }
pass() { printf 'PASS: %s\n' "$1"; }

# The installed payload, derived the way install.sh derives it — not hardcoded. install.sh's
# PAYLOAD_FILES assignment takes every file under .claude/ except state/, and its `for group in
# scripts` copy loop copies scripts/*.sh into .claude/scripts/ with exactly one exclusion,
# check-provenance.sh. A hardcoded list goes stale the first time the payload changes.
#
# (Corrected 2026-08-12. This block was written as `install.sh:175` and `:379-390`; Task 3 of this
# same wave inserted 29 lines above the copy loop and `:379-390` came to rest on licence prose. The
# shipped guard now carries the anchor form above — keep this listing in step with it.)
payload_paths() {
  ( cd "$REPO/.claude" && find . -type f ! -path './state/*' | sed 's|^\./|.claude/|' )
  for f in "$REPO"/scripts/*.sh; do
    [ -f "$f" ] || continue
    b="$(basename "$f")"
    # `[ x = y ] && continue` as the last command in a loop body exits 1 under set -e. Use if/then.
    if [ "$b" = "check-provenance.sh" ]; then continue; fi
    printf '.claude/scripts/%s\n' "$b"
  done
}
PAYLOAD="$(payload_paths)"

# Every Markdown file that ships.
SHIPPED_MD="$(find "$REPO/.claude" -name '*.md' | sort)"
MD_COUNT="$(printf '%s\n' "$SHIPPED_MD" | grep -c . || true)"

# 0. Coverage floors. A guard that silently stops reading its subject reports green forever. These
# are derived-with-headroom from the tree on 2026-08-11: 44 shipped .md files, 86 payload entries.
# Raise them when the tree grows; never lower one to make a run pass.
if [ "$MD_COUNT" -ge 35 ]; then
  pass "guard scanned $MD_COUNT shipped .md files (floor 35)"
else
  fail "guard scanned only $MD_COUNT shipped .md files — expected at least 35; it has stopped reading its subject"
fi

PAYLOAD_COUNT="$(printf '%s\n' "$PAYLOAD" | grep -c . || true)"
if [ "$PAYLOAD_COUNT" -ge 70 ]; then
  pass "payload derivation produced $PAYLOAD_COUNT entries (floor 70)"
else
  fail "payload derivation produced only $PAYLOAD_COUNT entries — expected at least 70; install.sh's layout has changed or the derivation is broken"
fi

# 1. No section marker in any shipped .md. The one exception is NOTICE.md's own §3, which names a
# section of the file it appears in and therefore resolves. §3[^0-9] so that a future §30 is caught.
sec_hits=""
while IFS= read -r md; do
  [ -n "$md" ] || continue
  m="$(grep -n '§[0-9]' "$md" || true)"
  [ -n "$m" ] || continue
  sec_hits="$sec_hits$(printf '%s\n' "$m" | sed "s|^|${md#"$REPO"/}:|")"$'\n'
done <<< "$SHIPPED_MD"

sec_bad="$(printf '%s' "$sec_hits" | grep -v '^\.claude/NOTICE\.md:[0-9][0-9]*:.*§3[^0-9]' || true)"
sec_bad_n="$(printf '%s' "$sec_bad" | grep -c . || true)"

if [ "$sec_bad_n" -eq 0 ]; then
  pass "no shipped surface carries a § section marker (NOTICE.md's own §3 excepted)"
else
  fail "$sec_bad_n shipped citation(s) carry a § marker that resolves to nothing:"
  printf '%s' "$sec_bad" | sed 's/^/       /'
fi

printf '\n%s\n' "--- test-shipped-citations.sh: $FAILURES failure(s) ---"
[ "$FAILURES" -eq 0 ]
```

- [ ] **Step 2: Run it and watch rule 1 fail with eight sites**

```bash
bash tests/test-shipped-citations.sh; echo "exit=$?"
```

Expected: `FAIL: 8 shipped citation(s) carry a § marker that resolves to nothing:` followed by the eight lines, and `exit=1`. The two floor assertions must both print `PASS`.

If the count is not 8, stop and report — the spec's before-state is measured, and a different number means the tree moved under the plan.

- [ ] **Step 3: Fix the seven markers that are pure deletions**

Each is the leading `§N — ` of a table cell. The prose that follows already carries the whole incident.

In `.claude/skills/verification-before-completion/SKILL.md`:

| Was | Becomes |
|---|---|
| `| §80 — a guard correctly refused a ` | `| A guard correctly refused a ` |
| `| §84 — five specs closed every finding` | `| Five specs closed every finding` |
| `| §86 — 39 skills, two multi-hour sessions` | `| 39 skills, two multi-hour sessions` |
| `| §82 — "zero \`Light2D\` references" asserted from grepping` | `| "zero \`Light2D\` references" asserted from grepping` |

In `.claude/skills/systematic-debugging/SKILL.md`:

| Was | Becomes |
|---|---|
| `| §77 — the MCP tool table is frozen` | `| The MCP tool table is frozen` |
| `| §82 — "zero \`Light2D\` references" asserted from a ` | `| "zero \`Light2D\` references" asserted from a ` |

In `.claude/skills/urp-pipeline/SKILL.md:363`, the Source cell ends:

```
the "grep misses editor-authored state" pattern is §82 in `sourced-incidents.md`
```

Replace with a citation that resolves — the row exists in a skill that ships:

```
the "grep misses editor-authored state" pattern is the one `.claude/skills/systematic-debugging/SKILL.md` records
```

Use the **path form**, not the bare skill name: `tests/test-surface-references.sh` flags a skill named without its `.claude/skills/<name>/SKILL.md` path.

- [ ] **Step 4: Fix the eighth — the cell that has no prose**

`.claude/skills/systematic-debugging/SKILL.md:39`'s entire Source cell is the string `§75`. `git log --all -S'§75'` returns one commit, `86db3fd`, which is the commit that created the line: nothing was lost and there is no incident to recover. **Do not invent one.**

The cell becomes `—`. The row's Reality column already carries the full argument. A single empty cell in a table where every other row is measured marks that row as reasoning rather than measurement, which is honest.

Was:

```
| "I should restart the session to get the bridge back" | The server's health is checkable over HTTP independently of whether this session can call it — "is the bridge up" and "can I reach it" have different remedies, and only one of them needs a restart. | §75 |
```

Becomes:

```
| "I should restart the session to get the bridge back" | The server's health is checkable over HTTP independently of whether this session can call it — "is the bridge up" and "can I reach it" have different remedies, and only one of them needs a restart. | — |
```

- [ ] **Step 5: Run the guard and watch rule 1 pass**

```bash
bash tests/test-shipped-citations.sh; echo "exit=$?"
grep -rn '§[0-9]' .claude | grep '\.md:'
```

Expected: `PASS: no shipped surface carries a § section marker`, `exit=0`, and the `grep` returning exactly one line — `.claude/NOTICE.md:25`, carrying `§3`.

- [ ] **Step 6: Create the ledger**

Create `docs/superpowers/plans/2026-08-11-shipped-citations-resolve-ledger.md`. Line one is this plan's path. Record the base commit `99c18a2`, the two gate commands, and one open item per task. Open the two standing sections the loop keeps — *Standing facts for every dispatch* and *Interfaces produced so far* — seeding the first from this plan's Global Constraints.

- [ ] **Step 7: Add provenance rows and run both gates**

Append two rows to `provenance.tsv` (tabs, not spaces). The plan's own row already exists — it was
committed with the plan.

```
tests/test-shipped-citations.sh	original	-	-	-	original	guards that every citation a shipped surface makes resolves in an installed project: no §N marker, and no backticked token naming a repo file the payload does not carry
docs/superpowers/plans/2026-08-11-shipped-citations-resolve-ledger.md	original	-	-	-	original	execution ledger for the shipped-citations plan; tracked beside the plan per spec D8
```

Then:

```bash
bash scripts/check-provenance.sh | tail -2
bash tests/run-tests.sh 2>&1 | tail -20
```

Expected: `provenance OK`, and the suite green with the new file's section present.

- [ ] **Step 8: Verify the runner discovered the new file**

```bash
bash tests/run-tests.sh 2>&1 | tee /tmp/suite.log
sed $'s/\x1b\\[[0-9;]*m//g' /tmp/suite.log | grep -c '^--- test-.*\.sh ---'
ls tests/test-*.sh | wc -l
```

Expected: the two numbers equal, and one higher than before this task (30 → 31).

- [ ] **Step 9: Commit**

```bash
git add tests/test-shipped-citations.sh provenance.tsv \
        docs/superpowers/plans/2026-08-11-shipped-citations-resolve.md \
        docs/superpowers/plans/2026-08-11-shipped-citations-resolve-ledger.md \
        .claude/skills/verification-before-completion/SKILL.md \
        .claude/skills/systematic-debugging/SKILL.md \
        .claude/skills/urp-pipeline/SKILL.md
git commit -m "fix(surfaces): eight citations pointed at a document that never existed

sourced-incidents.md is absent from the tree, from provenance.tsv, and from
provenance-skip.tsv, and git log --all --diff-filter=D returns nothing for it.
Seven of the eight markers are deleted with their prose intact — the Source
cell always carried the incident. The eighth, systematic-debugging:39, was a
cell containing nothing but the string; it becomes an em dash rather than an
invented incident."
```

- [ ] **Step 10: Regenerate the baseline in its own commit**

```bash
python3 -m tools.kinglet_build baseline-regenerate --anchor HEAD --expect-drift 3 --dry-run
```

Three `.claude/` files changed; each is categorised, so the tool may report six. **Use the tool's numbers.** Re-run without `--dry-run`, fold in any `tests/kinglet/test_baseline_inventory.py` constants that went red, run `bash tests/run-tests.sh`, then commit as `chore(baseline): record the eight § citations removed`.

---

## Task 2: The guard's rule 2, and the eight repo-only paths

**Files:**
- Modify: `tests/test-shipped-citations.sh`
- Modify: `.claude/NOTICE.md:49`, `:149`, `:197`
- Modify: `.claude/rules/pc-console.md:6`, `:43`
- Modify: `.claude/skills/verification-before-completion/SKILL.md:38-40`

**Interfaces:**
- Consumes: `payload_paths()` and `PAYLOAD` from Task 1.
- Produces: nothing later tasks call.

- [ ] **Step 1: Add rule 2 to the guard**

Insert before the closing `printf`/`[ "$FAILURES" -eq 0 ]` lines of `tests/test-shipped-citations.sh`:

```bash
# 2. No backticked token that names a real file in this repository and is absent from the payload.
#
# Resolving against the repository tree is what keeps this from firing on user-project paths:
# `docs/features/<slug>/design.md` names no file here, so it is never flagged, while
# `tests/test-no-mobile.sh` names one and does not ship.
#
# The escape is a URL, in the same file, whose own text ends with the cited path. File-scoped, not
# block-scoped: NOTICE.md is one document, and a reader who meets "linked at the top of this file"
# scrolls up and finds the link. Block-scoped would force a URL into NOTICE.md:140's table header,
# `| How `provenance.tsv` records it |`, which names the manifest rather than pointing at it.
# Matching the URL's *text* is what stops it being a loophole: NOTICE.md carries five URLs and none
# ends in test-provenance-origins.sh, so that citation still fires.
#
# Three tokens are allowed. Each is a name collision the measurement turned up, not a citation of a
# repository-only artifact. If this list grows, rule 2 is wrong — re-examine it, do not append.
#   CLAUDE.md  the user's own file, generated by /unity-init; cited in 26 shipped files, correctly
#   LICENSE    in NOTICE.md this is always an upstream's licence ("everything-claude-unity's
#              `LICENSE`"); a root LICENSE here caused the match
#   VERSION    NOTICE.md:41 lists .claude/VERSION, which ships; a root VERSION here caused the match
CITATION_ALLOW="CLAUDE.md LICENSE VERSION"

path_bad=""
path_count=0
tokens_seen=0
while IFS= read -r md; do
  [ -n "$md" ] || continue
  rel="${md#"$REPO"/}"
  urls="$(grep -oE 'https?://[^ )>]+' "$md" || true)"
  toks="$(grep -oE '`[A-Za-z0-9_][A-Za-z0-9_./-]*`' "$md" | tr -d '`' | sort -u || true)"
  while IFS= read -r t; do
    [ -n "$t" ] || continue
    tokens_seen=$((tokens_seen + 1))
    # Only tokens that name a real file here can dangle in a user's project.
    [ -f "$REPO/$t" ] || continue
    case " $CITATION_ALLOW " in *" $t "*) continue ;; esac
    case "$t" in
      .claude/*) p="$t" ;;
      scripts/*) p=".claude/$t" ;;
      *)         p="" ;;
    esac
    # Here-string, never a pipe: grep -q exits on first match without draining stdin, and under
    # pipefail that SIGPIPEs the writer.
    if [ -n "$p" ] && grep -qxF -- "$p" <<< "$PAYLOAD"; then continue; fi
    esc="$(printf '%s' "$t" | sed 's/[.[\*^$]/\\&/g')"
    if [ -n "$urls" ] && grep -qE -- "/${esc}\$" <<< "$urls"; then continue; fi
    path_bad="$path_bad       $rel: $t"$'\n'
    path_count=$((path_count + 1))
  done <<< "$toks"
done <<< "$SHIPPED_MD"

if [ "$tokens_seen" -ge 200 ]; then
  pass "guard examined $tokens_seen backticked tokens (floor 200)"
else
  fail "guard examined only $tokens_seen backticked tokens — expected at least 200; the token expression has stopped matching"
fi

if [ "$path_count" -eq 0 ]; then
  pass "no shipped surface cites a repository path the installed payload does not carry"
else
  fail "$path_count shipped citation(s) name a file install.sh does not copy:"
  printf '%s' "$path_bad"
fi
```

- [ ] **Step 2: Run it and watch rule 2 fail with the eight sites the spec names**

```bash
bash tests/test-shipped-citations.sh; echo "exit=$?"
```

Expected: `FAIL: 8 shipped citation(s) name a file install.sh does not copy:` listing exactly

```
       .claude/NOTICE.md: CREDITS.md
       .claude/NOTICE.md: scripts/check-provenance.sh
       .claude/NOTICE.md: tests/test-provenance-origins.sh
       .claude/rules/pc-console.md: provenance-skip.tsv
       .claude/rules/pc-console.md: tests/test-no-mobile.sh
       .claude/skills/verification-before-completion/SKILL.md: install.sh
       .claude/skills/verification-before-completion/SKILL.md: tests/test-bash32-compat.sh
       .claude/skills/verification-before-completion/SKILL.md: tests/test-surface-references.sh
```

`provenance.tsv` must **not** appear — it is cited four times in `NOTICE.md` and cleared by the URL at `:12`. If it appears, the URL escape is broken; stop and report rather than editing `NOTICE.md:29`, `:135` or `:140`, which the spec explicitly leaves alone.

`PASS: guard examined <n> backticked tokens` must also print, with `n` in the mid-500s — **561** measured on 2026-08-12 (`bash tests/test-shipped-citations.sh`), 569 before the fixes.

*(This line read "near 323" until 2026-08-12. 323 was a count of *globally unique* tokens; `tokens_seen` increments once per (file, token) pair, so it is roughly 1.7× that. A red-first expectation off by 238 makes a broken derivation indistinguishable from a stale estimate — and the floor the guard actually enforces is 200, which both numbers clear. The ledger ruled "fix the plan text, not the guard"; this is that fix, applied.)*

- [ ] **Step 3: Fix `.claude/rules/pc-console.md`**

`:6` — drop the parenthetical entirely. Was:

```
and the mobile genre skills were removed at build time, not disabled (see `provenance-skip.tsv`), and
```

Becomes:

```
and the mobile genre skills were removed at build time, not disabled, and
```

`:43` — the instruction is the defect. A rule cannot tell a reader to inspect a file they do not have and report a regression. Was:

```
disabled — and `tests/test-no-mobile.sh` keeps it out. If you find any, that test has regressed;
treat it as a bug and report it.)
```

Becomes:

```
disabled — and the toolkit's own suite keeps it out. If you find any, report it as a bug.)
```

- [ ] **Step 4: Fix `.claude/skills/verification-before-completion/SKILL.md`**

`install.sh` is cited on **two** rows (`:39` and `:40`). Rule 2 reports per (file, token), so fixing one leaves the token flagged. Fix both.

`:38` was:

```
| `tests/test-surface-references.sh`, seen to fail before being trusted; and the runner-provided test file that "exits 0 having asserted nothing" |
```

Becomes:

```
| A guard in the toolkit's own suite, seen to fail before being trusted; and the runner-provided test file that "exits 0 having asserted nothing" |
```

`:39` was:

```
| `tests/test-bash32-compat.sh` excluded `install.sh`, which then shipped the SIGPIPE bug the test exists to catch (2026-08-03, `git log 0f772a4..HEAD`) |
```

Becomes:

```
| A bash-compatibility check that excluded the installer, which then shipped the SIGPIPE bug the check exists to catch (2026-08-03) |
```

`:40` — the `install.sh` reference is inside a longer sentence. Was:

```
reasoning from `install.sh` and eight existing references, and had it changed to `mcp__unityMCP__`
```

Becomes:

```
reasoning from the installer and eight existing references, and had it changed to `mcp__unityMCP__`
```

- [ ] **Step 5: Fix `.claude/NOTICE.md`**

`:49` — the instruction's audience is by definition working in an installed project. Was:

```
makes it attributable and `tests/test-provenance-origins.sh` fails until the second exists.
```

Becomes:

```
makes it attributable and the toolkit's suite fails until the second exists.
```

`:149` — was:

```
**No automated check in the toolkit verifies the Superpowers pin.** `scripts/check-provenance.sh`
compares checksums only for rows marked `status=verbatim`, and its `--online` pass additionally only
```

Becomes:

```
**No automated check in the toolkit verifies the Superpowers pin.** The manifest checker
compares checksums only for rows marked `status=verbatim`, and its `--online` pass additionally only
```

`:197` — this one is fixed by making the pointer resolve, in the shape `:12` already uses. Was:

```
See the toolkit repository's `CREDITS.md` for the same record at more detail.
```

Becomes:

```
See the toolkit repository's `CREDITS.md` for the same record at more detail:

> https://github.com/OmerZeyveli/kinglet-unity/blob/main/CREDITS.md
```

The URL then clears the token by the same rule that flagged it — confirm that in Step 6 rather than assuming it.

- [ ] **Step 6: Run the guard and watch rule 2 pass**

```bash
bash tests/test-shipped-citations.sh; echo "exit=$?"
```

Expected: `PASS: no shipped surface cites a repository path the installed payload does not carry`, all four floor/rule assertions `PASS`, `exit=0`.

- [ ] **Step 7: Mutation-prove the guard on all three of its parts**

Each mutation is made on a **scratch copy of the tree**, never on the working tree. Run, observe, discard.

```bash
scratch=$(mktemp -d); git archive HEAD | tar -x -C "$scratch"; cd "$scratch"

# (a) rule 1 fires on a new marker
printf '\nSee §99 for the measurement.\n' >> .claude/skills/state-machine/SKILL.md
bash tests/test-shipped-citations.sh; echo "expect exit=1, got $?"
git checkout .claude/skills/state-machine/SKILL.md

# (b) rule 2 fires on a new repo-only path
printf '\nSee `tests/test-no-mobile.sh` for the check.\n' >> .claude/skills/state-machine/SKILL.md
bash tests/test-shipped-citations.sh; echo "expect exit=1, got $?"
git checkout .claude/skills/state-machine/SKILL.md

# (c) the allow-list is load-bearing, not decorative
sed -i 's/^CITATION_ALLOW="CLAUDE.md /CITATION_ALLOW="/' tests/test-shipped-citations.sh
bash tests/test-shipped-citations.sh 2>&1 | grep -c 'CLAUDE.md'
```

Expected: (a) and (b) both `exit=1` naming the injected line; (c) reports **26** files — proving the guard reads the whole shipped set rather than a subset. Then `cd -` and `rm -rf "$scratch"`.

Record the three observed results in the ledger. If (c) reports a number well below 26, the guard is not reading what it claims to and the task is not done.

- [ ] **Step 8: Run both gates and commit**

```bash
bash scripts/check-provenance.sh | tail -2
bash tests/run-tests.sh 2>&1 | tail -20
git add tests/test-shipped-citations.sh .claude/NOTICE.md .claude/rules/pc-console.md \
        .claude/skills/verification-before-completion/SKILL.md
git commit -m "fix(surfaces): eight citations named files the installer does not copy

install.sh ships .claude/ plus scripts/*.sh less check-provenance.sh; tests/
is copied by nothing and an installed .claude/tests/ is pruned. pc-console.md
was a shipped rule telling the reader to inspect test-no-mobile.sh and report
a regression.

provenance.tsv is untouched: its four NOTICE.md sites are cleared by the URL
at :12, which is what the file-scoped escape exists for. CREDITS.md gets the
same treatment rather than losing the reference."
```

- [ ] **Step 9: Regenerate the baseline in its own commit**

`--dry-run` first, use the tool's numbers, fold in any red constants, commit as `chore(baseline): record the eight repo-only citations fixed`.

---

## Task 3: The installer's dry-run states what the real run does

**Files:**
- Modify: `install.sh:257`
- Test: `bash tests/fixtures/mkproject.sh` + `bash install.sh --dry-run`

**Interfaces:**
- Consumes: nothing.
- Produces: nothing.

- [ ] **Step 1: Observe the defect against a real fixture**

```bash
bash tests/fixtures/mkproject.sh /tmp/citefix-p
bash install.sh --project-dir /tmp/citefix-p --dry-run 2>&1 | grep -A4 'Would install:'
```

Expected: the output contains `scripts/ and tests/ into .claude/`.

Then confirm the real run does not do that — read the comment block in `install.sh` that opens *"Validation scripts ship alongside the payload. The test suite does not."*, immediately above the `for group in scripts` copy loop (`grep -n 'Validation scripts ship alongside' install.sh`; `:385-416` on 2026-08-12). It states `tests/` deliberately does not ship and that an installed `.claude/tests/` is **pruned** by the payload-prune above it; the loop is `for group in scripts`.

*(This step read "`install.sh:370-390`" until 2026-08-12. This task's own +29-line insertion moved that block, so the instruction sent a later reader to the paragraph about `provenance.tsv` not shipping and to licence prose — a step whose own edit invalidated its own citation.)*

- [ ] **Step 2: Fix the line**

`install.sh:257` was:

```bash
  printf '  scripts/ and tests/ into .claude/\n'
```

Becomes:

```bash
  printf '  scripts/ into .claude/\n'
```

- [ ] **Step 3: Prove the dry-run and the real run now agree**

```bash
rm -rf /tmp/citefix-p && bash tests/fixtures/mkproject.sh /tmp/citefix-p
bash install.sh --project-dir /tmp/citefix-p --dry-run 2>&1 | grep -A4 'Would install:'
bash install.sh --project-dir /tmp/citefix-p >/dev/null 2>&1
ls /tmp/citefix-p/.claude/
```

Expected: the dry-run no longer mentions `tests/`, and the installed `.claude/` contains `scripts/` and no `tests/`. Any directory present after the real run that the dry-run did not announce is a second instance of this defect — report it rather than fixing it silently, since it is outside this task's brief.

- [ ] **Step 4: Run both gates and commit**

```bash
bash tests/run-tests.sh 2>&1 | tail -20
bash scripts/check-provenance.sh | tail -2
git add install.sh
git commit -m "fix(install): the dry-run promised a directory the real run removes

:257 printed 'scripts/ and tests/ into .claude/'. The real run ships scripts
only, and the payload-prune removes an installed .claude/tests/ left by an
older version. The dry-run is what a user reads before consenting; it does not
get to describe a different program."
```

`install.sh` is not under `.claude/`, so no baseline regeneration is needed — confirm with `python3 -m tools.kinglet_build baseline-regenerate --anchor HEAD --expect-drift 0 --dry-run` and report if it disagrees.

---

## Task 4: The fork states its threshold once

**Files:**
- Modify: `.claude/skills/subagent-driven-implementation/SKILL.md` (frontmatter `description:`)
- Modify: `tests/test-surface-references.sh`

**Interfaces:**
- Consumes: nothing.
- Produces: nothing.

- [ ] **Step 1: Read both descriptions and confirm the contradiction**

```bash
sed -n '1,4p' .claude/skills/unity-execution/SKILL.md
sed -n '1,4p' .claude/skills/subagent-driven-implementation/SKILL.md
```

`unity-execution` says prefer `subagent-driven-implementation` when the plan has **more than one substantial task**. `subagent-driven-implementation` says prefer itself when the plan has **more than one task**. A plan with two small tasks matches both.

- [ ] **Step 2: Write the failing assertion**

Add to `tests/test-surface-references.sh`. This file is **runner-provided** — it uses the runner's `assert_contains` / `$REPO_DIR` and defines neither, so `bash tests/test-surface-references.sh` exits 0 having asserted nothing. Verify through the runner only.

```bash
# The fork's threshold is stated once. unity-execution and subagent-driven-implementation are the
# two branches of unity-planning's fork, and a reader chooses between them by their description:
# fields — so both must carry the same boundary, verbatim. They did not: "more than one substantial
# task" against a bare "more than one task", which sent a two-trivial-task plan to the expensive
# branch against the reason that branch exists.
exec_desc="$(sed -n '1,6p' "$REPO_DIR/.claude/skills/unity-execution/SKILL.md")"
sdd_desc="$(sed -n '1,6p' "$REPO_DIR/.claude/skills/subagent-driven-implementation/SKILL.md")"

assert_contains "$exec_desc" "more than one substantial task" \
  "unity-execution states the fork threshold as 'more than one substantial task'"
assert_contains "$sdd_desc" "more than one substantial task" \
  "subagent-driven-implementation states the same threshold, verbatim"

# The negative half. "more than one substantial task" does not contain "more than one task", so this
# is a real assertion rather than one satisfied by the positive above.
for f in unity-execution subagent-driven-implementation; do
  if grep -qF -- "more than one task" <<< "$(sed -n '1,6p' "$REPO_DIR/.claude/skills/$f/SKILL.md")"; then
    fail_test "$f still carries the bare 'more than one task' threshold"
  else
    pass_test "$f does not carry a second, looser threshold"
  fi
done
```

Match the helper names this file already uses — read its existing assertions and copy the idiom rather than assuming `fail_test` / `pass_test` are what the runner provides.

- [ ] **Step 3: Run through the runner and watch it fail**

```bash
bash tests/run-tests.sh 2>&1 | sed -n '/--- test-surface-references/,/^---/p' | tail -30
```

Expected: a failure naming `subagent-driven-implementation still carries the bare 'more than one task' threshold`. A pass here means the assertion is not reading what it claims to — fix the assertion before touching the skill.

- [ ] **Step 4: Fix the description**

`.claude/skills/subagent-driven-implementation/SKILL.md` frontmatter, was:

```
Prefer this over inline execution when the plan has more than one task, or when a task is large enough that its own context would crowd out review.
```

Becomes:

```
Prefer this over inline execution when the plan has more than one substantial task, or when a task is large enough that its own context would crowd out review.
```

One word. `unity-execution` already carries the surviving form and is not edited.

- [ ] **Step 5: Run through the runner and watch it pass**

```bash
bash tests/run-tests.sh 2>&1 | sed -n '/--- test-surface-references/,/^---/p' | tail -30
```

- [ ] **Step 6: Run both gates and commit**

```bash
bash scripts/check-provenance.sh | tail -2
git add .claude/skills/subagent-driven-implementation/SKILL.md tests/test-surface-references.sh
git commit -m "fix(surfaces): the fork stated its threshold twice, differently

A plan with two small tasks matched both branches: unity-execution said prefer
the subagent loop above 'more than one substantial task', the subagent loop
said prefer itself above 'more than one task'. The bare form routes a
two-trivial-task plan to the expensive branch against the reason inline
execution exists, so it is the one that goes."
```

- [ ] **Step 7: Regenerate the baseline in its own commit**

One `.claude/` file changed. `--dry-run` first, use the tool's numbers, commit as `chore(baseline): record the fork's single threshold`.

---

## Task 5: The two documents that contradict themselves

**Files:**
- Modify: `docs/GETTING-STARTED.md:162`
- Modify: `docs/superpowers/plans/2026-08-10-kinglet-process-chain-ledger.md:12-30`

**Interfaces:**
- Consumes: nothing.
- Produces: nothing.

- [ ] **Step 1: Confirm both contradictions**

```bash
sed -n '155,163p' docs/GETTING-STARTED.md
sed -n '12,30p' docs/superpowers/plans/2026-08-10-kinglet-process-chain-ledger.md
grep -n 'Whole-branch review\|Product fixes P2' docs/superpowers/plans/2026-08-10-kinglet-process-chain-ledger.md
```

`GETTING-STARTED.md:157` names `unity-brainstorming` as the chain's entry; `:162`, five lines later, sends a new user to `/unity-prototype` "to see the full pipeline in action" — the single documented exemption from that chain. The ledger's `RESUME HERE` says "Tasks 1–7 are done and closed. Only verification remains" and "Task 8 is next", while its own task table marks all eight done plus a whole-branch review and the P2/P4/P8 fixes.

- [ ] **Step 2: Fix `docs/GETTING-STARTED.md:162`**

Was:

```
Start with `/unity-init`, then `/unity-doctor` to get a baseline. From there, try `/unity-review` on existing code or `/unity-prototype` to see the full pipeline in action.
```

Becomes:

```
Start with `/unity-init`, then `/unity-doctor` to get a baseline. From there, anything you want to build starts at `unity-brainstorming` — it hands to `unity-planning`, which chooses how the work is executed. `/unity-review` on existing code and `/unity-prototype` for a throwaway scene are the two entry points that stand outside that chain, which is what makes them a good first look rather than the pipeline itself.
```

- [ ] **Step 3: Fix the ledger's `RESUME HERE`**

Replace the stale block at `:12-30` with the wave's actual end state: all eight tasks done, the whole-branch review done, the owner-selected P2/P4/P8 fixes done, and the branch unmerged with P1/P3 deferred to their own round. Keep the section's purpose — it exists so a controller that has lost its context can resume — so state what is *open*, not only what closed.

Do not delete the reading list at `:39-41` or the cut-criterion paragraph at `:32-37`; both are still true and still worth reading.

- [ ] **Step 4: Run both gates and commit**

```bash
bash tests/run-tests.sh 2>&1 | tail -20
bash scripts/check-provenance.sh | tail -2
git add docs/GETTING-STARTED.md docs/superpowers/plans/2026-08-10-kinglet-process-chain-ledger.md
git commit -m "docs: a new user's first look pointed at the one chain-exempt surface

GETTING-STARTED:157 names unity-brainstorming as the chain's entry and :162,
five lines later, sent the reader to /unity-prototype 'to see the full
pipeline in action' — the single documented exemption from that chain. The
process-chain ledger carried the same class: RESUME HERE said seven of eight
tasks were done while its own table marked all eight plus two later rounds."
```

Neither file is under `.claude/`, so no baseline regeneration is expected — confirm with a `--dry-run` and report a disagreement.

---

## Task 6: Whole-wave verification

**Files:** none modified unless a check fails.

**Interfaces:**
- Consumes: everything Tasks 1–5 produced.
- Produces: the verification record in the ledger.

- [ ] **Step 1: Re-run the spec's acceptance criteria, all seven**

```bash
# 1. suite green, discovery honest
bash tests/run-tests.sh 2>&1 | tee /tmp/suite.log | tail -5
sed $'s/\x1b\\[[0-9;]*m//g' /tmp/suite.log | grep -c '^--- test-.*\.sh ---'
ls tests/test-*.sh | wc -l

# 2. manifest
bash scripts/check-provenance.sh | tail -2

# 3. exactly one § remains, and it is NOTICE.md's own
grep -rn '§[0-9]' .claude | grep '\.md:'

# 4. the guard's flag set is empty
bash tests/test-shipped-citations.sh; echo "exit=$?"

# 6. the installer's dry-run and real run agree
rm -rf /tmp/citefix-v && bash tests/fixtures/mkproject.sh /tmp/citefix-v
bash install.sh --project-dir /tmp/citefix-v --dry-run 2>&1 | grep -A4 'Would install:'
bash install.sh --project-dir /tmp/citefix-v >/dev/null 2>&1 && ls /tmp/citefix-v/.claude/

# 7. one threshold, stated identically — flattened, because it wraps
for f in .claude/skills/unity-execution/SKILL.md \
         .claude/skills/subagent-driven-implementation/SKILL.md; do
  tr '\n' ' ' < "$f" | grep -oE 'more than one[[:space:]]+[a-z]+' | sort -u
done
```

Expected: suite green with the two counts equal; `provenance OK`; one `§` line, `.claude/NOTICE.md:25`; guard `exit=0`; dry-run naming no directory the real run omits; and every `more than one …` occurrence reading `more than one substantial`.

**The line-oriented form this step originally carried does not work here**, and would have read as a failed fix: `grep -h 'more than one'` prints **three** lines, not two, because `unity-execution` states the threshold a third time in its body at `:10-11` — and that occurrence wraps mid-phrase, so the middle line ends at a bare `more than one` with `substantial task` on the next. A Task 6 implementer comparing against "the two lines" would see a third line that looks exactly like the defect this wave removed. Flatten first. Found by Task 4's implementer, confirmed by its reviewer.

Criterion 5 (mutation proof) was executed in Task 2 Step 7 and its three results recorded in the ledger — cite them, do not re-run.

- [ ] **Step 2: Sweep for the class rather than the instances**

The instances are fixed; the question is whether the class is closed. Run the guard's own logic against surfaces it does **not** cover, and record what you find without fixing it — that is the spin-out wave's work.

```bash
# Does anything outside .claude/*.md cite a repo-only path in a shipped context?
# Scoped to .claude/ — the payload — because that is what the question is about.
grep -rn 'sourced-incidents' .claude/ || echo "clean: no reference survives in the shipped payload"

# Do the hooks and shipped scripts cite paths that do not ship?
grep -n 'tests/' .claude/hooks/*.sh .claude/scripts/*.sh 2>/dev/null || echo "clean"
```

*(The first sweep was `grep -rn 'sourced-incidents' . --exclude-dir=.git` until 2026-08-12, and it could never print clean: every hit is in this wave's own spec, plan and ledger — documents that must name the string in order to discuss it, and that do not ship. The ledger's Task 6 amendment ruled it be scoped to `.claude/` and rewrote it in the ledger only; this is that ruling applied to the plan. The repo-wide count is unstable by construction — it rises by one every time a document discusses the sweep, because discussing it means naming the string — which is the second reason not to write the check that way. The scoped form returns nothing, stably.)*

Record both results in the ledger. A hit in the second is a real finding for the spin-out wave, not for this one.

- [ ] **Step 3: Verify the working tree is clean and the branch is coherent**

```bash
git status --short
git log --oneline 99c18a2..HEAD
git diff --stat 99c18a2..HEAD
```

Expected: clean tree, and a commit per task plus its baseline commit.

- [ ] **Step 4: Close the ledger**

Record: each task's commit range, every deferred finding with its ruling, the three mutation results from Task 2 Step 7, the two sweep results from Step 2, and what remains open — P1 and P3, and the spin-out wave. State plainly what was *not* verified: nothing here proves the toolkit behaves correctly inside Claude Code, only that the installer places correct bytes.

- [ ] **Step 5: Commit the ledger**

```bash
git add docs/superpowers/plans/2026-08-11-shipped-citations-resolve-ledger.md
git commit -m "chore(ledger): close the shipped-citations wave"
```

---

## Self-Review

**Spec coverage.** D1 → Tasks 1–2 (both rules). D2 → Task 1 Step 3. D3 → Task 1 Step 4. D4 → Task 1 Step 1, `payload_paths()`. D5 → Task 1 Step 1 (rule 1) and Task 2 Step 1 (rule 2, with the file-scoped URL escape). D6 → Task 2 Step 1's `CITATION_ALLOW`, proven load-bearing in Step 7(c). D7 → Task 2 Steps 3–5, all eight rows. D8 → Task 3. D9 → Task 4. D10 → Task 5. Acceptance criteria 1–7 → Task 6 Step 1, with criterion 5 cited from Task 2 Step 7 rather than re-run.

**Placeholder scan.** No "TBD", no "handle edge cases", no "similar to Task N". Every code step carries the actual text. Two places delegate judgment deliberately and say so: Task 1 Step 10's baseline number (the tool's number wins over the plan's estimate, which is a stated constraint rather than a placeholder) and Task 4 Step 2's helper names (read the file's existing idiom — naming them here would be guessing at a runner interface this plan has not measured).

**Type consistency.** `payload_paths()` and `PAYLOAD` are defined in Task 1 Step 1 and consumed in Task 2 Step 1 under the same names. `SHIPPED_MD` and `FAILURES` likewise. `CITATION_ALLOW` is introduced and used only in Task 2. The guard's file name is `tests/test-shipped-citations.sh` everywhere, including its provenance row and its self-identifying footer line.

**One gap found and closed while reviewing:** the spec's flag list names `install.sh` once for `verification-before-completion`, but the file cites it on two rows (`:39` and `:40`) and rule 2 reports per (file, token) — fixing one would leave the token flagged with no obvious cause. Task 2 Step 4 now says so explicitly and fixes both.
