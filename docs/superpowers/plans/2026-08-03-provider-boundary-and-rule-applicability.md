# Provider Boundary and Rule Applicability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop Kinglet asserting an architecture the target project does not use, and make a written plan a first-class input to the engineering track.

**Architecture:** Five tasks against three files. `scripts/generate-claude-md.sh` learns to detect the VContainer/MessagePipe/UniTask stack and emit one section saying which rules bind — the rule files themselves are never deleted or conditionally installed, because field note 87 measured that deleting one changed nothing while a sentence naming it changed everything. `.claude/commands/unity-workflow.md` learns to accept a plan path. `scripts/studio-doctor.sh` learns to catch a stale provider declaration.

**Tech Stack:** bash 3.2-compatible shell, the `tests/run-tests.sh` harness, `scripts/check-provenance.sh`, `tools.kinglet_build` for baseline regeneration.

**Authority:** `docs/superpowers/specs/2026-08-03-provider-boundary-and-rule-applicability-design.md`. Where this plan and that spec disagree, the spec wins and the disagreement is a bug in this plan — report it rather than working around it.

## Global Constraints

- **Bash 3.2 (macOS) compatible.** No `declare -A`. No `grep -oP` / `grep -qP` — GNU-only.
- **Do not pipe into a reader that can exit early** under `set -euo pipefail`. `head` and `grep -q` both do. Use a here-string (`grep -qF -- "$needle" <<< "$haystack"`) or `awk` over the file.
- **Validate an argument before `shift 2`** — `shift` fails under `set -u` before the error message prints.
- **`bash tests/run-tests.sh` must pass at every commit, with every test file present in its output.** Count the `--- test-*.sh ---` headers with ANSI stripped and compare to `ls tests/test-*.sh | wc -l`. The summary line is not evidence. Currently 22 files, 217 assertions; both drift.
- **`scripts/check-provenance.sh` must report `provenance OK` at every commit.** A new file with no row fails as an orphan.
- **Two test idioms coexist, and mixing them produces a silent false pass.** `tests/run-tests.sh:211` runs each file as `( source "$test_file" )` — sourced into a subshell. A file may therefore either (a) define its own assertion helpers and be runnable standalone with `bash`, as `tests/test-templates.sh` does, or (b) use the runner's helpers (`assert_contains`, `assert_eq`, `assert_file_exists`) and `$REPO_DIR`, as `tests/test-studio-doctor.sh` does — in which case **`bash <file>` is not a valid way to run it.** Measured 2026-08-03: `bash tests/test-studio-doctor.sh` exits **0 having asserted nothing**, because the helpers are undefined, `$REPO_DIR` is empty, and the file sets no `-e`. New files in this plan (Tasks 1 and 3) use idiom (a). Task 5 appends to an existing idiom-(b) file and must follow (b) and run through the runner.
- **`scripts/generate-claude-md.sh` writes the document to STDOUT and every log line to STDERR.** The caller owns the destination file. Violating this destroyed a user's `CLAUDE.md` once; the header comment records how.
- **`emit_marked_region` is the single producer of the marked region.** `--facts-only` and full generation must stay byte-identical inside the markers. They disagreed before `89c661c` and the documented in-place refresh silently deleted a heading every time.
- **Editing anything under `.claude/` drifts `migration/baseline-inventory.json`.** Regenerate with `python3 -m tools.kinglet_build baseline-regenerate --anchor <commit> --expect-drift <n>` in a **separate** commit. Run `--dry-run` first to learn the count; it refuses if the path set changed or the count is not what you predicted, and that refusal is the point. Tasks 1, 2, 4 and 5 touch only `scripts/` and `tests/` and need no regeneration. **Task 3 does.**
- **`--expect-drift` counts tracked entries, not files.** The baseline records each `.claude/` path **twice** — once under `full_claude_tree.files` and once under `categories.<kind>.files` — so a one-file change is `--expect-drift 2`, not 1. Measured 2026-08-03 on `.claude/commands/unity-workflow.md`. An earlier draft of this plan said 1, the dry-run refused, and the implementer escalated instead of adjusting the number to make it pass. That is the correct response and it is why the guard exists: had the drift been 2 for some *other* reason, raising the number would have hidden a real change. Never tune `--expect-drift` to whatever the tool reports — derive it, and if it disagrees, find out why before changing it.
- **Provider choice must not live under `.claude/state/`.** `.gitignore` lines 44-45 ignore `.claude/state/*` except `.gitkeep`, and the platform design requires provider choice to be *"project configuration, not hidden client state"*. It is passed as a flag and re-derived on every run.

---

### Task 1: Detect the stack and declare which rules bind

**Files:**
- Modify: `scripts/generate-claude-md.sh` — add detection after the package block (after line 142), add `emit_stack_verdict`, call it from `emit_marked_region`
- Modify: `tests/fixtures/mkproject.sh` — add a `legacy` variant
- Create: `tests/test-rule-applicability.sh`
- Modify: `provenance.tsv` — one row for the new test file

**Interfaces:**
- Consumes: `$PROJECT_DIR`, `$MANIFEST`, `$DETECTED_PACKAGES` — all already defined in the script.
- Produces: shell variables `VC_PRESENT`, `MP_PRESENT`, `UT_PRESENT` (each `yes`/`no`/`manifest-only`), `CS_FILE_COUNT`, `COROUTINE_FILES`, and the function `emit_stack_verdict`. Task 2 reads `VC_PRESENT` and `MP_PRESENT`. Task 4 calls `emit_stack_verdict` unchanged.

- [ ] **Step 1: Add the `legacy` fixture variant**

The existing variants are `urp|builtin|bare|dirty`; `urp` and `dirty` both carry VContainer and UniTask, so nothing today exercises the "does not bind" path.

In `tests/fixtures/mkproject.sh`, extend the usage comment on line 9 and the usage string on line 19 to read `--variant urp|builtin|bare|dirty|legacy`, add the doc line after the `dirty` line in the header comment:

```
#   legacy   URP, no VContainer/MessagePipe/UniTask, coroutine-using scripts — the "does not bind" path
```

Then add a `legacy` arm to the `case "$VARIANT"` block, immediately before `bare) ;;`:

```bash
  legacy)
    cat > "$DIR/Packages/manifest.json" <<'JSON'
{
  "dependencies": {
    "com.unity.render-pipelines.universal": "17.0.3",
    "com.unity.inputsystem": "1.8.2"
  }
}
JSON
    # First-party code that uses coroutines and none of the mandated stack. Two files, because
    # a single file cannot distinguish "counted once" from "counted per match".
    cat > "$DIR/Assets/Scripts/Spawner.cs" <<'CS'
using System.Collections;
using UnityEngine;

public class Spawner : MonoBehaviour
{
    private void Start() { StartCoroutine(SpawnLoop()); }
    private IEnumerator SpawnLoop() { yield return new WaitForSeconds(1f); }
}
CS
    cat > "$DIR/Assets/Scripts/Fader.cs" <<'CS'
using System.Collections;
using UnityEngine;

public class Fader : MonoBehaviour
{
    private void OnEnable() { StartCoroutine(Fade()); }
    private IEnumerator Fade() { yield return null; }
}
CS
    # Vendored code that DOES reference the stack. If detection counts this, it reports every
    # project as using VContainer, which is the failure this fixture exists to catch.
    mkdir -p "$DIR/Assets/Extensions/SomeVendor"
    cat > "$DIR/Assets/Extensions/SomeVendor/VendorThing.cs" <<'CS'
using VContainer;
using Cysharp.Threading.Tasks;

public class VendorThing
{
    // The literal string "UniTask" is deliberate, not decoration: detection greps for it, and
    // this member is what lets this file also guard the pruning of the UniTask count, not just
    // VContainer's. Do not "clean up" this to a bare using-directive.
    private UniTask _pending;
}
CS
    ;;
```

Also add `legacy` to the `--variant` validation on line 81 by extending the final `*)` arm's message — no code change needed there, the new arm handles it.

- [ ] **Step 2: Write the failing test**

Create `tests/test-rule-applicability.sh`:

```bash
#!/usr/bin/env bash
# ============================================================================
# test-rule-applicability.sh — the generated CLAUDE.md must state which rules
# bind, based on what the project actually contains, and must never assert a
# stack it did not detect.
#
# Why this exists: measured in Endless-Evolution/Assets on 2026-08-03 —
# VContainer 0 files, MessagePipe 0, UniTask 1, against 130 using
# StartCoroutine, while .claude/rules/architecture.md mandates the first three.
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
GEN="$PROJECT_ROOT/scripts/generate-claude-md.sh"
MK="$PROJECT_ROOT/tests/fixtures/mkproject.sh"
TMP="${TMPDIR:-/tmp}/kinglet-rule-applicability.$$"
trap 'rm -rf "$TMP"' EXIT

TESTS_RUN=0; TESTS_PASSED=0; TESTS_FAILED=0
assert_eq() {
    TESTS_RUN=$((TESTS_RUN+1))
    if [ "$1" = "$2" ]; then TESTS_PASSED=$((TESTS_PASSED+1)); echo "PASS: $3"
    else TESTS_FAILED=$((TESTS_FAILED+1)); echo "FAIL: $3 (expected '$2', got '$1')"; fi
}
# grep -qF on a here-string, never on a pipe: grep -q exits on first match without
# draining stdin, and under pipefail that SIGPIPEs the writer. See CLAUDE.md.
assert_has() {
    TESTS_RUN=$((TESTS_RUN+1))
    if grep -qF -- "$2" <<< "$1"; then TESTS_PASSED=$((TESTS_PASSED+1)); echo "PASS: $3"
    else TESTS_FAILED=$((TESTS_FAILED+1)); echo "FAIL: $3 (missing '$2')"; fi
}
assert_lacks() {
    TESTS_RUN=$((TESTS_RUN+1))
    if grep -qF -- "$2" <<< "$1"; then TESTS_FAILED=$((TESTS_FAILED+1)); echo "FAIL: $3 (unexpectedly found '$2')"
    else TESTS_PASSED=$((TESTS_PASSED+1)); echo "PASS: $3"; fi
}

echo ""
echo "=== Rule Applicability Tests ==="
echo ""

# ── Case 1: legacy project — the stack is absent and code exists ───────────
echo "--- Case: stack absent, first-party code present ---"
bash "$MK" "$TMP/legacy" --variant legacy >/dev/null
OUT_LEGACY="$(bash "$GEN" "$TMP/legacy" 2>/dev/null)"
assert_has "$OUT_LEGACY" "Architecture stack" "legacy project emits the stack section"
assert_has "$OUT_LEGACY" "do not bind" "legacy project says the architecture rules do not bind"
assert_has "$OUT_LEGACY" "architecture.md" "legacy project names the rule file it is disapplying"
assert_lacks "$OUT_LEGACY" "recommended for this new project" "legacy project is not treated as greenfield"

# The vendored file under Assets/Extensions/ references VContainer and UniTask. If the
# scan counted it, VC_REFS would be 1 and this row would read "yes (1 file(s))".
#
# Match the whole rendered row, not a loose two-word phrase. An earlier draft of this
# plan asserted the absence of "VContainer yes", which the emitted format — pipe, space,
# value — can never contain, so it passed whether or not detection was broken. This
# assertion is the only guard on the vendored-file trap in the fixture; it has to be able
# to fail.
assert_has "$OUT_LEGACY" "| VContainer | no (0 file(s)) |" \
    "vendored code does not count as the project using the stack"
assert_has "$OUT_LEGACY" "| UniTask | no (0 file(s)) |" \
    "vendored UniTask reference does not count either"

# ── Case 2: urp fixture — VContainer and UniTask are in the manifest ───────
echo ""
echo "--- Case: stack present in the manifest ---"
bash "$MK" "$TMP/urp" --variant urp >/dev/null
OUT_URP="$(bash "$GEN" "$TMP/urp" 2>/dev/null)"
assert_has "$OUT_URP" "Architecture stack" "urp project emits the stack section"
assert_lacks "$OUT_URP" "do not bind" "urp project does not disapply the architecture rules"

# ── Case 3: bare fixture — no scripts at all ──────────────────────────────
echo ""
echo "--- Case: greenfield ---"
bash "$MK" "$TMP/bare" --variant bare >/dev/null
OUT_BARE="$(bash "$GEN" "$TMP/bare" 2>/dev/null)"
assert_has "$OUT_BARE" "recommended for this new project" "greenfield says recommended, not detected"
assert_lacks "$OUT_BARE" "do not bind" "greenfield does not disapply anything"

# ── Case 4: --facts-only and full generation agree inside the markers ──────
# This is the regression fixed in 89c661c. The new section lives inside the
# marked region, so it is exactly the kind of content that can drift again.
echo ""
echo "--- Case: --facts-only matches the marked region byte for byte ---"
FACTS="$(bash "$GEN" --facts-only "$TMP/legacy" 2>/dev/null)"
REGION="$(bash "$GEN" "$TMP/legacy" 2>/dev/null \
    | awk '/kinglet:generated:begin/{f=1;next} /kinglet:generated:end/{f=0} f')"
assert_eq "$FACTS" "$REGION" "--facts-only equals the marked region of a full generation"

# ── Case 5: stdout/stderr contract ────────────────────────────────────────
echo ""
echo "--- Case: log lines never contaminate the document ---"
ERRTXT="$(bash "$GEN" "$TMP/legacy" 2>&1 >/dev/null)"
assert_has "$ERRTXT" "[INFO]" "info lines go to stderr"
assert_lacks "$OUT_LEGACY" "[INFO]" "info lines are absent from stdout"

echo ""
echo "=== Rule Applicability: $TESTS_PASSED/$TESTS_RUN passed, $TESTS_FAILED failed ==="
[ "$TESTS_FAILED" -eq 0 ]
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `bash tests/test-rule-applicability.sh`
Expected: FAIL. The `legacy` variant now exists (Step 1), so the fixture builds, but `generate-claude-md.sh` emits no "Architecture stack" section — every assertion looking for it fails.

- [ ] **Step 4: Add detection to `generate-claude-md.sh`**

Insert after the package-detection block (after `info "Detected $PKG_COUNT package(s) of interest."`, currently line 142):

```bash
# ---------------------------------------------------------------------------
# 3b. Architecture stack — detected, never assumed
#
# .claude/rules/architecture.md mandates VContainer, MessagePipe, UniTask and
# Model-View-System; unity-specifics.md bans coroutines. Measured in the only
# real game project using this toolkit on 2026-08-03: VContainer 0 files,
# MessagePipe 0, UniTask 1, against 130 using StartCoroutine. Asserting a stack
# the project does not have is the largest single source of wrong guidance this
# toolkit ships, so it is detected and declared instead.
#
# WHAT IS SCANNED, and why it is not the obvious thing:
#   - Primary signal: Packages/manifest.json.
#   - Secondary signal: Assets/ ONLY, with vendored subtrees pruned.
# Scanning Packages/ would find the dependency's own source and report every
# project as using it. Vendored subtrees matter for the same reason at smaller
# scale: Endless-Evolution carries 923 third-party .cs files under
# Assets/Extensions/. A symbol found only in vendored code is not the project
# using it.
#
# One pass over the file list, testing all four symbols per file, rather than
# four passes: on a 1000-script project the difference is four thousand grep
# invocations against one thousand.
# ---------------------------------------------------------------------------
CS_FILE_COUNT=0
VC_REFS=0; MP_REFS=0; UT_REFS=0; COROUTINE_FILES=0

while IFS= read -r cs_file; do
    [ -n "$cs_file" ] || continue
    CS_FILE_COUNT=$((CS_FILE_COUNT + 1))
    # sort -u drains its input; no early-exit reader in this pipeline.
    hits=$(grep -o -e 'VContainer' -e 'MessagePipe' -e 'UniTask' -e 'StartCoroutine' \
                "$cs_file" 2>/dev/null | sort -u | tr '\n' ' ')
    case "$hits" in *VContainer*)     VC_REFS=$((VC_REFS + 1)) ;; esac
    case "$hits" in *MessagePipe*)    MP_REFS=$((MP_REFS + 1)) ;; esac
    case "$hits" in *UniTask*)        UT_REFS=$((UT_REFS + 1)) ;; esac
    case "$hits" in *StartCoroutine*) COROUTINE_FILES=$((COROUTINE_FILES + 1)) ;; esac
done < <(find "$PROJECT_DIR/Assets" \
              \( -name Extensions -o -name Plugins -o -name ThirdParty -o -name Vendor \) -prune -o \
              -name '*.cs' -print 2>/dev/null || true)

# manifest_has <package-id> — the manifest is the primary signal.
manifest_has() {
    [ -f "$MANIFEST" ] || return 1
    grep -q "\"$1\"" "$MANIFEST"
}

# present <manifest-id> <ref-count> -> yes | manifest-only | no
#
# "manifest-only" is a real third state, not a rounding of "yes". A package
# declared and never used means the project has not committed to it, and this
# generator does not get to decide that for them.
present() {
    if manifest_has "$1"; then
        if [ "$2" -gt 0 ]; then printf 'yes'; else printf 'manifest-only'; fi
    elif [ "$2" -gt 0 ]; then printf 'yes'
    else printf 'no'; fi
}

VC_PRESENT=$(present jp.hadashikick.vcontainer "$VC_REFS")
MP_PRESENT=$(present com.cysharp.messagepipe  "$MP_REFS")
UT_PRESENT=$(present com.cysharp.unitask      "$UT_REFS")

info "Architecture stack: VContainer=$VC_PRESENT MessagePipe=$MP_PRESENT UniTask=$UT_PRESENT" \
     "(first-party .cs: $CS_FILE_COUNT, using StartCoroutine: $COROUTINE_FILES)"
```

- [ ] **Step 5: Add `emit_stack_verdict` and call it**

Insert immediately before `emit_marked_region` (currently line 265):

```bash
# The section that stops this document asserting a stack the project does not
# have. It states which rules bind; it never deletes or disables a rule file.
#
# Field note 87, 2026-08-03: twelve headless runs, architecture.md present in
# one arm and deleted in the other. All twelve converged on the same design,
# and one run in the DELETED arm still wrote "not .claude/rules/architecture.md
# (no VContainer/MessagePipe here — see CLAUDE.md)". It rejected a file that was
# not there, because CLAUDE.md named it. The bulk layer steered nothing; one
# precedence sentence steered everything. Hence a sentence, not a deletion.
emit_stack_verdict() {
    echo ""
    echo "### Architecture stack — detected, not assumed"
    echo ""

    if [ "$CS_FILE_COUNT" -eq 0 ]; then
        echo "No first-party C# found under \`Assets/\` yet, so nothing is detected and nothing is"
        echo "contradicted. The toolkit's default stack — Model-View-System with VContainer,"
        echo "MessagePipe and UniTask — is **recommended for this new project**, and every rule in"
        echo "\`.claude/rules/\` binds. Re-run the generator once there is code; if the project goes"
        echo "another way, this section will say so."
        return
    fi

    echo "Scanned \`Assets/\` (vendored subtrees excluded), $CS_FILE_COUNT first-party C# file(s):"
    echo ""
    echo "| Dependency | Present |"
    echo "|---|---|"
    echo "| VContainer | $VC_PRESENT ($VC_REFS file(s)) |"
    echo "| MessagePipe | $MP_PRESENT ($MP_REFS file(s)) |"
    echo "| UniTask | $UT_PRESENT ($UT_REFS file(s)) |"
    echo "| \`StartCoroutine\` | $COROUTINE_FILES file(s) |"
    echo ""

    # architecture.md rests on VContainer + MessagePipe. Either one present is
    # enough to keep it binding; "manifest-only" is deliberately neither.
    if [ "$VC_PRESENT" = yes ] || [ "$MP_PRESENT" = yes ]; then
        echo "\`.claude/rules/architecture.md\` **binds in full.**"
    elif [ "$VC_PRESENT" = manifest-only ] || [ "$MP_PRESENT" = manifest-only ]; then
        echo "A dependency is declared in \`Packages/manifest.json\` but used in no first-party file."
        echo "**This generator takes no side.** Decide whether \`.claude/rules/architecture.md\` binds"
        echo "here and write the answer in the Vision half of this document, outside the markers."
    else
        echo "\`.claude/rules/architecture.md\` **does not bind in this project** — its Model-View-System,"
        echo "VContainer and MessagePipe sections describe a stack this code does not use. Follow the"
        echo "architecture the code actually has. The rest of that file — \`ScriptableObjects for Static"
        echo "Data\`, \`Input System Architecture\`, \`No God Objects\`, \`Composition Over Inheritance\` —"
        echo "is architecture-agnostic and **does** apply."
    fi

    echo ""
    if [ "$UT_PRESENT" = yes ]; then
        echo "The \"No Coroutines — Use UniTask\" section of \`unity-specifics.md\` **binds.**"
    elif [ "$COROUTINE_FILES" -gt 0 ]; then
        echo "The \"No Coroutines — Use UniTask\" section of \`unity-specifics.md\` **does not bind** —"
        echo "$COROUTINE_FILES file(s) here use \`StartCoroutine\` and UniTask is not in use."
    else
        echo "Neither UniTask nor \`StartCoroutine\` appears; the async guidance in \`unity-specifics.md\`"
        echo "stands as a recommendation."
    fi

    echo ""
    echo "\`csharp-unity.md\`, \`performance.md\`, \`serialization.md\`, \`pc-console.md\` and the rest of"
    echo "\`unity-specifics.md\` **bind in full** regardless — they are architecture-agnostic, and"
    echo "\`[FormerlySerializedAs]\` and \`== null\` are exactly the rules that catch silent data loss."
}
```

Then add one line to `emit_marked_region`, between `emit_facts` and the trailing `echo ""`:

```bash
emit_marked_region() {
    echo ""
    echo "## Project Facts (auto-detected)"
    echo ""
    emit_facts
    emit_stack_verdict
    echo ""
}
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `bash tests/test-rule-applicability.sh`
Expected: all assertions PASS, exit 0.

Then run the whole suite and the manifest:

```bash
bash tests/run-tests.sh 2>&1 | tail -4
bash scripts/check-provenance.sh 2>&1 | tail -3
bash tests/run-tests.sh 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -c -- "--- test-.*\.sh ---"
ls tests/test-*.sh | wc -l
```

Expected: `Failed: 0`; `provenance OK`; the last two numbers equal, and one higher than before this task.

- [ ] **Step 7: Add the provenance row**

The new test file has no row, so `check-provenance.sh` fails it as an orphan. Append (tab-separated, seven fields):

```bash
printf 'tests/test-rule-applicability.sh\toriginal\t-\t-\t-\toriginal\tasserts the generated CLAUDE.md declares which rules bind rather than assuming\n' >> provenance.tsv
```

`tests/fixtures/mkproject.sh` already has a row and is `origin=original`, so editing it needs no status change — but check: `grep mkproject provenance.tsv`. If its status is not `original`, stop and report rather than guessing.

- [ ] **Step 8: Commit**

```bash
git add scripts/generate-claude-md.sh tests/fixtures/mkproject.sh tests/test-rule-applicability.sh provenance.tsv
git commit -m "feat(generate-claude-md): detect the architecture stack and say which rules bind

Measured in Endless-Evolution/Assets: VContainer 0 files, MessagePipe 0,
UniTask 1, against 130 using StartCoroutine, while architecture.md mandates
the first three and unity-specifics.md bans coroutines.

The rule files are not deleted and not conditionally installed. Field note 87
measured twelve headless runs with architecture.md present and deleted: all
twelve converged on the same design, and one run in the deleted arm rejected
the file by name because CLAUDE.md named it. A sentence, not a deletion.

Scans Assets/ only, vendored subtrees pruned. Scanning Packages/ would find
the dependency's own source and report every project as using it; the legacy
fixture carries a vendored file under Assets/Extensions/ that references
VContainer precisely to catch that."
```

---

### Task 2: Stop the static Engineering Stance from contradicting the detected section

**Files:**
- Modify: `scripts/generate-claude-md.sh:317-328` (the `## Engineering Stance` block in the static tail)
- Modify: `tests/test-rule-applicability.sh` — two assertions

**Interfaces:**
- Consumes: nothing new. This is prose in a `cat <<'MDEOF'` heredoc.
- Produces: nothing later tasks read.

**Why this task exists, and why it is separate.** Task 1's section lands inside the marked region. The `## Engineering Stance` block sits in the *static tail*, at line 317, **outside** the markers — so it is written once on first generation and never refreshed by `--facts-only`. It currently states, unconditionally:

> *"Architecture: Model-View-System (MVS) with VContainer (DI), MessagePipe … UniTask (async — no coroutines)"*

Left alone, a legacy project's generated `CLAUDE.md` says the stack is fixed in one section and does not apply in another, in the same file, permanently. The detected section is the one grounded in evidence, so the static block must defer to it rather than compete.

- [ ] **Step 1: Write the failing assertions**

Append to `tests/test-rule-applicability.sh`, before the final summary block:

```bash
# ── Case 6: the static tail does not contradict the detected section ───────
# The Engineering Stance block is emitted once, outside the markers, and never
# refreshed. If it asserts the stack unconditionally it will permanently
# contradict the section Task 1 emits.
echo ""
echo "--- Case: static Engineering Stance defers to detection ---"
assert_lacks "$OUT_LEGACY" "Model-View-System (MVS) with **VContainer**" \
    "Engineering Stance does not assert the stack unconditionally"
assert_has "$OUT_LEGACY" "Architecture stack — detected, not assumed" \
    "Engineering Stance points at the detected section"
```

- [ ] **Step 2: Run to verify it fails**

Run: `bash tests/test-rule-applicability.sh`
Expected: FAIL on "Engineering Stance does not assert the stack unconditionally" — the string is present at line 320.

- [ ] **Step 3: Rewrite the Architecture bullet**

In the static tail heredoc, replace these three lines (currently 320-322):

```
- **Architecture:** Model-View-System (MVS) with **VContainer** (DI), **MessagePipe** (cross-system
  messaging — no singletons or static event buses), **UniTask** (async — no coroutines), and the
  **New Input System** (legacy `Input.*` is blocked by a hook).
```

with:

```
- **Architecture:** see **Architecture stack — detected, not assumed** in the generated block above.
  That section is measured against this project's code and it is the authority; this list is not.
  The toolkit's default is Model-View-System with VContainer (DI), MessagePipe (cross-system
  messaging) and UniTask (async), and it is a default, not a finding.
- **Input:** the **New Input System**. Legacy `Input.*` is blocked by a hook, so this one is
  enforced rather than recommended.
```

The New Input System moves to its own bullet because it is the one item in that list that is actually enforced — `block-legacy-input.sh` stopped an `Input.GetKey` edit in a real project on 2026-08-02 — and burying an enforced rule inside a list of defaults misreports both.

Then, in the `**Rules** live in` bullet immediately below, replace `— the spine.` with:

```
    `unity-specifics.md` — the spine, **subject to the detected-stack section above.**
```

- [ ] **Step 4: Run to verify it passes**

Run: `bash tests/test-rule-applicability.sh` — all PASS.
Then: `bash tests/run-tests.sh 2>&1 | tail -4` — `Failed: 0`.

Note that `tests/test-install.sh` and `tests/test-pioneer-identity.sh` may assert on generated `CLAUDE.md` text. If either fails, **read the assertion before changing it**: if it pins the old unconditional wording, update it and say so in the commit message; if it pins something else that broke, stop and report.

- [ ] **Step 5: Commit**

```bash
git add scripts/generate-claude-md.sh tests/test-rule-applicability.sh
git commit -m "fix(generate-claude-md): the static stance no longer contradicts the detected stack

The Engineering Stance block sits outside the generated markers, so it is
written once and never refreshed. Asserting MVS/VContainer/MessagePipe/UniTask
there meant a legacy project's CLAUDE.md would state the stack is fixed in one
section and does not apply in another, in the same file, permanently.

It now defers to the detected section and calls its own list a default rather
than a finding. The New Input System moves to its own bullet: it is the one
item in that list that is actually enforced, by block-legacy-input.sh, and
burying it among defaults misreports both."
```

---

### Task 3: A written plan is a first-class input to `/unity-workflow`

**Files:**
- Modify: `.claude/commands/unity-workflow.md` — frontmatter `args`, and Phase 1
- Modify: `provenance.tsv` — update the `note` on the `unity-workflow.md` row
- Create: `tests/test-workflow-plan-input.sh`
- Modify: `provenance.tsv` — row for the new test file
- Separate commit: `migration/baseline-inventory.json`

**Interfaces:**
- Consumes: nothing from Tasks 1-2.
- Produces: nothing Tasks 4-5 read.

This is Pioneer Item 2 (Break 2 — *"the two tracks do not connect"*) with the source set widened to include a process provider's output alongside a GDD.

- [ ] **Step 1: Write the failing test**

Create `tests/test-workflow-plan-input.sh`:

```bash
#!/usr/bin/env bash
# ============================================================================
# test-workflow-plan-input.sh — /unity-workflow must accept a written plan as
# input, not only a free-text feature description.
#
# This is frontmatter and prose, so what a bash test can prove is narrow: that
# the contract is stated, that the search order is written down, and that the
# verbatim rule is present. Whether the model actually adopts a plan handed to
# it is prompt behaviour and no assertion here claims to cover it.
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
WF="$PROJECT_ROOT/.claude/commands/unity-workflow.md"

TESTS_RUN=0; TESTS_PASSED=0; TESTS_FAILED=0
assert_has() {
    TESTS_RUN=$((TESTS_RUN+1))
    if grep -qF -- "$2" <<< "$1"; then TESTS_PASSED=$((TESTS_PASSED+1)); echo "PASS: $3"
    else TESTS_FAILED=$((TESTS_FAILED+1)); echo "FAIL: $3 (missing '$2')"; fi
}

echo ""
echo "=== Workflow Plan-Input Tests ==="
echo ""

BODY="$(cat "$WF")"
# The first description:/args: inside the first --- block. Three command files
# carry a second description: in example output in the body; keying off the
# frontmatter fence is what keeps this honest.
FRONT="$(awk 'NR==1 && /^---$/{f=1;next} f && /^---$/{exit} f' "$WF")"

assert_has "$FRONT" "args: feature-description-or-plan-path" "frontmatter accepts a plan path"
assert_has "$BODY" "docs/features/" "Phase 1 names the features plan location"
assert_has "$BODY" "docs/superpowers/plans/" "Phase 1 names the provider plan location"
assert_has "$BODY" "docs/design/" "Phase 1 names the design-doc location"
assert_has "$BODY" "verbatim" "acceptance criteria are carried verbatim"
assert_has "$BODY" "Hard stop" "an unreadable named plan is a hard stop"

echo ""
echo "=== Workflow Plan-Input: $TESTS_PASSED/$TESTS_RUN passed, $TESTS_FAILED failed ==="
[ "$TESTS_FAILED" -eq 0 ]
```

- [ ] **Step 2: Run to verify it fails**

Run: `bash tests/test-workflow-plan-input.sh`
Expected: FAIL on every assertion — `args:` currently reads `feature_description` and Phase 1 names no paths.

- [ ] **Step 3: Change the frontmatter**

In `.claude/commands/unity-workflow.md`, line 5:

```
args: feature-description-or-plan-path
```

Leave `description:` alone. Rewriting descriptions is Wave 1b-2 Task 3, deferred behind two gates named in the spec — do not start it here.

- [ ] **Step 4: Add the adoption step to Phase 1**

Insert immediately after the `## Phase 1: Clarify` heading, before "Interview the user":

```markdown
### Phase 1a: Adopt an existing plan, if there is one

Before interviewing anyone, look for work that has already been scoped. `$ARGUMENTS` may be a
path to a written plan or spec rather than a feature description.

Search in this order and stop at the first hit:

1. `$ARGUMENTS` itself, if it resolves to a readable file
2. `docs/features/<slug>/plan.md`
3. `docs/superpowers/plans/*<slug>*.md` — a process provider's output is as legitimate an input
   as a design document
4. `docs/design/<system>.md`

**Found:** skip the interview. Carry the plan's **Acceptance Criteria**, and its
**Game Feel → Feel Acceptance Criteria** if present, into the Requirements Summary **verbatim**.
Verbatim matters: a paraphrase is a silent design change. Record which file was adopted, by path,
in the Requirements Summary, so a later session can tell where the requirements came from.

**Found, but it has no acceptance criteria:** adopt what is there and state plainly what was
missing. Never invent the criteria the plan would have contained.

**More than one match:** list them and ask. Never silently take the newest.

**`$ARGUMENTS` names a file that cannot be read:** **Hard stop.** Say the path and the reason, and
stop. Do not fall back to interviewing as though nothing was asked for — a silent degradation into
conversation is invisible to the user and is exactly how requirements stopped surviving sessions
in the first place.

**Nothing found:** say so in one line, then run the interview below.
```

- [ ] **Step 5: Run to verify it passes**

Run: `bash tests/test-workflow-plan-input.sh` — all PASS.

- [ ] **Step 6: Update provenance for both files**

`unity-workflow.md` is already `origin=ecu status=modified`, so no status flip is needed — but its `note` reads `mobile-strip` and now understates what diverged. Change that row's note to:

```
mobile-strip; phase-1a-adopts-a-written-plan
```

And add a row for the new test file:

```bash
printf 'tests/test-workflow-plan-input.sh\toriginal\t-\t-\t-\toriginal\tasserts /unity-workflow accepts a written plan as input\n' >> provenance.tsv
```

Run `bash scripts/check-provenance.sh` — expected `provenance OK`.

- [ ] **Step 7: Commit the change**

```bash
git add .claude/commands/unity-workflow.md tests/test-workflow-plan-input.sh provenance.tsv
git commit -m "feat(unity-workflow): a written plan is a first-class input

Pioneer Item 2 (Break 2 — the two tracks do not connect), with the source set
widened: a process provider's plan under docs/superpowers/plans/ is as
legitimate an input as a GDD under docs/design/.

Acceptance criteria are carried verbatim, because a paraphrase is a silent
design change. A named plan that cannot be read is a hard stop, not a silent
fall back to interviewing — that degradation is invisible to the user and is
how requirements stopped surviving sessions.

description: is deliberately untouched. The description rewrite is Wave 1b-2
Task 3, deferred behind the two gates named in the design spec."
```

- [ ] **Step 8: Regenerate the baseline in a separate commit**

`.claude/` changed, so `migration/baseline-inventory.json` has drifted by exactly one path.

```bash
python3 -m tools.kinglet_build baseline-regenerate --anchor "$(git rev-parse HEAD)" --expect-drift 2 --dry-run
```

Expected: **2 changes**, both of them the same path — `.claude/commands/unity-workflow.md` is recorded once under `full_claude_tree.files` and once under `categories.commands.files`, and `--expect-drift` counts entries rather than files. If it reports a different count or a changed path set, **stop** — that refusal is the tool working, and it means something else changed that this plan did not account for. Report it, and do not raise the number until you know why.

Then re-run without `--dry-run` and commit:

```bash
git add migration/baseline-inventory.json
git commit -m "chore(baseline): record unity-workflow.md after phase 1a"
```

---

### Task 4: Declare provider ownership in one sentence

**Files:**
- Modify: `scripts/generate-claude-md.sh` — a `--provider` flag and one paragraph in `emit_stack_verdict`'s sibling
- Modify: `install.sh` — detection, the prompt, and passing the flag through
- Modify: `tests/test-rule-applicability.sh` — three assertions

**Interfaces:**
- Consumes: `emit_marked_region` from Task 1.
- Produces: `generate-claude-md.sh --provider <name|none>`; Task 5 reads the emitted sentence.

**Constraints from the platform design, which are not negotiable here.** Kinglet *"does not copy, uninstall, disable, or secretly shadow the detected plugin"*, and provider choice is *"project configuration, not hidden client state"*. So: the sentence lands in the git-tracked `CLAUDE.md`; the user's global settings are read but never written; and nothing is persisted under `.claude/state/`, which `.gitignore` lines 44-45 exclude from the repository.

`install.sh` reads nothing from `$HOME` today. This is its first user-global read and it is therefore constrained: read-only, path overridable for tests, and benign in absence.

- [ ] **Step 1: Write the failing assertions**

Append to `tests/test-rule-applicability.sh`, before the summary block:

```bash
# ── Case 7: provider declaration ──────────────────────────────────────────
echo ""
echo "--- Case: provider declaration ---"
OUT_PROV="$(bash "$GEN" --provider superpowers "$TMP/legacy" 2>/dev/null)"
assert_has "$OUT_PROV" "owned by \`superpowers\`" "declared provider is named"
assert_has "$OUT_PROV" "/unity-interview" "the surface that yields is named"
assert_lacks "$OUT_LEGACY" "owned by" "no provider flag means no sentence"

# The sentence lives inside the markers, so a --facts-only refresh must carry it.
FACTS_PROV="$(bash "$GEN" --facts-only --provider superpowers "$TMP/legacy" 2>/dev/null)"
assert_has "$FACTS_PROV" "owned by \`superpowers\`" "--facts-only carries the provider sentence"
```

- [ ] **Step 2: Run to verify it fails**

Run: `bash tests/test-rule-applicability.sh`
Expected: FAIL — `--provider` is an unknown option, so the script exits 2 and `OUT_PROV` is empty.

- [ ] **Step 3: Add the flag and the sentence**

In the arg loop (currently lines 48-55), add before the `-*)` arm:

```bash
        --provider)   [ $# -ge 2 ] || { error "--provider needs a value"; exit 2; }
                      PROVIDER="$2"; shift 2 ;;
```

The `[ $# -ge 2 ]` guard is not decoration: `shift 2` with one argument left fails under `set -u` *before* an error message can print, and the user gets a silent exit 1.

Initialise beside `FACTS_ONLY=0`:

```bash
PROVIDER=""
```

Then add to `emit_marked_region`, after `emit_stack_verdict`:

```bash
    emit_provider_verdict
```

and define it beside `emit_stack_verdict`:

```bash
# One sentence, not a routing block. Field note 87 measured that the bulk
# auto-loaded layer steered nothing while a single precedence sentence steered
# everything; a block here would be paying for the part that did not work.
emit_provider_verdict() {
    [ -n "$PROVIDER" ] || return 0
    [ "$PROVIDER" != none ] || return 0
    echo ""
    echo "### Process provider"
    echo ""
    echo "Discovery and written planning in this project are owned by \`$PROVIDER\`."
    echo "\`/unity-interview\` yields to it and does not compete for the discovery stage."
    echo "Unity implementation, Unity verification and Unity domain knowledge stay with this toolkit."
}
```

- [ ] **Step 4: Add detection and the prompt to `install.sh`**

Near the other option variables (line 71), add:

```bash
PROVIDER_CHOICE=""
# Overridable so the test suite can point at a fixture instead of the real home
# directory. install.sh reads nothing else from $HOME; this read is the first,
# it is read-only, and its absence is benign.
CLAUDE_USER_SETTINGS="${KINGLET_USER_SETTINGS:-$HOME/.claude/settings.json}"
```

Add the detection and prompt immediately before the `GEN=` line (currently 314):

```bash
# ── Process provider — detect, propose, never assume ────────────────────────
# The platform design requires that Kinglet propose a detected provider and the
# user approve it, and that Kinglet never copy, disable, or shadow it. Detection
# is read-only and re-run on every install, so no choice is persisted: if the
# provider is uninstalled later, the next refresh drops the sentence, which is
# the correct behaviour.
if [ -f "$CLAUDE_USER_SETTINGS" ] \
   && grep -q '"superpowers@claude-plugins-official"[[:space:]]*:[[:space:]]*true' "$CLAUDE_USER_SETTINGS"; then
  if [ "$ASSUME_YES" -eq 1 ] || [ ! -t 0 ]; then
    # The safe default is no declaration: it changes nothing about how the
    # project behaves today.
    info "Superpowers detected; --yes takes the safe default (no provider declaration)."
  else
    echo "  Superpowers is installed for your user account."
    echo "  Kinglet can record it as this project's discovery and planning provider."
    echo "  This writes one sentence into CLAUDE.md. It does not modify Superpowers"
    echo "  or your global settings."
    read -rp "  Record it? [y/N]: " REPLY_PROVIDER
    case "$REPLY_PROVIDER" in [yY]*) PROVIDER_CHOICE="superpowers" ;; esac
  fi
fi
```

Then find the call site that runs `"$GEN"` and add the flag. There is one, and it may appear twice (full generation and `--facts-only` refresh) — **both** must pass it, or an in-place refresh silently drops the sentence. That is the same defect class as the heading `--facts-only` used to delete, fixed in `89c661c`. Add to each invocation:

```bash
${PROVIDER_CHOICE:+--provider "$PROVIDER_CHOICE"}
```

- [ ] **Step 5: Run to verify it passes**

Run: `bash tests/test-rule-applicability.sh` — all PASS.

Then exercise the installer end to end against a fixture with a fake user settings file:

```bash
bash tests/fixtures/mkproject.sh /tmp/prov --variant legacy
mkdir -p /tmp/fakehome/.claude
printf '{"enabledPlugins":{"superpowers@claude-plugins-official":true}}\n' > /tmp/fakehome/.claude/settings.json
KINGLET_USER_SETTINGS=/tmp/fakehome/.claude/settings.json \
  bash install.sh --project-dir /tmp/prov --yes
grep -c "owned by" /tmp/prov/CLAUDE.md
```

Expected: `0`. `--yes` takes the safe default, so no sentence is written. This confirms the non-interactive path does not make a choice on the user's behalf.

- [ ] **Step 6: Commit**

```bash
git add scripts/generate-claude-md.sh install.sh tests/test-rule-applicability.sh
git commit -m "feat(install): record a detected process provider, once the user says so

One sentence in the marked region, not a routing block: field note 87 measured
that the bulk auto-loaded layer steered nothing and a single precedence
sentence steered everything.

Detection is read-only, re-run every install, and persisted nowhere. If the
provider is uninstalled the next refresh drops the sentence. Nothing is written
under .claude/state/, which .gitignore excludes — the platform design requires
provider choice to be project configuration, not hidden client state.

install.sh read nothing from \$HOME before this. The path is overridable via
KINGLET_USER_SETTINGS so the suite can point at a fixture, and its absence is
benign. --yes takes the safe default and declares nothing."
```

---

### Task 5: `studio-doctor` catches a stale provider declaration

**Files:**
- Modify: `scripts/studio-doctor.sh`
- Modify: `tests/test-studio-doctor.sh`

**Interfaces:**
- Consumes: the `### Process provider` section emitted by Task 4.
- Produces: nothing.

The platform design's *"if the active provider later disappears or becomes incompatible, doctor offers the built-in provider as an explicit fallback"*, made concrete. This is a `warn`, never a `fail`: the project still works, the declaration is just no longer true, and `studio-doctor.sh` exits 1 only on `fail`.

- [ ] **Step 1: Write the failing test**

**Read this before writing the test.** `tests/run-tests.sh:211` runs each test file as
`( source "$test_file" )` — a subshell, but **sourced**, not executed. So a test file may use the
runner's helpers (`assert_contains`, `assert_not_contains`, `assert_eq`, `assert_file_exists`) and
the runner's `$REPO_DIR` without defining either. `tests/test-studio-doctor.sh` does exactly that.

Two consequences bind this task:

- Use the runner's helpers and `$REPO_DIR`. Do **not** define local ones and do not introduce
  `$PROJECT_ROOT` — that variable does not exist in this file.
- **`bash tests/test-studio-doctor.sh` is not a valid way to run it.** Standalone, the helpers are
  undefined, `$REPO_DIR` is empty, and the file has no `set -e` — measured on 2026-08-03, it exits
  **0 having asserted nothing**. A verification step built on it would report a pass in both
  directions and the TDD cycle would have no red phase at all.

Append to `tests/test-studio-doctor.sh`, in that file's existing style:

```bash
# ── A declared provider that is not installed is a WARN, not a FAIL ────────
echo ""
echo "--- Test: stale provider declaration ---"
TSD_STALE="/tmp/kinglet-doctor-stale-$$"
bash "${REPO_DIR}/tests/fixtures/mkproject.sh" "$TSD_STALE" --variant urp >/dev/null
bash "${REPO_DIR}/install.sh" --project-dir "$TSD_STALE" --yes >/dev/null 2>&1
printf '\n### Process provider\n\nDiscovery and written planning in this project are owned by `superpowers`.\n' \
  >> "$TSD_STALE/CLAUDE.md"

TSD_STALE_OUT="$(KINGLET_USER_SETTINGS=/nonexistent-on-purpose \
  bash "$TSD_DOCTOR" --project-dir "$TSD_STALE" 2>&1 || true)"
assert_contains "$TSD_STALE_OUT" "superpowers" \
    "doctor names the declared provider"
assert_contains "$TSD_STALE_OUT" "not" \
    "doctor says the declared provider is not installed"
assert_contains "$TSD_STALE_OUT" "/unity-interview" \
    "doctor names the built-in fallback"
rm -rf "$TSD_STALE"
```

- [ ] **Step 2: Run to verify it fails**

Run the file through the runner, which is the only way its helpers exist:

```bash
bash tests/run-tests.sh 2>&1 | sed 's/\x1b\[[0-9;]*m//g' \
  | sed -n '/--- test-studio-doctor.sh ---/,/^--- test-/p'
```

Expected: the three new assertions appear as **FAIL** — `studio-doctor.sh` has no such check yet, so
its output names no provider. If they appear as PASS before you have written any implementation,
stop and report: it means the assertions are matching something incidental in the existing output
rather than the check this task adds.

- [ ] **Step 3: Add the check**

In `scripts/studio-doctor.sh`, add before the summary block (currently line 249), using the file's existing `pass` / `warn` helpers:

```bash
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
    elif [ -f "$USER_SETTINGS" ] && grep -q "\"$declared@" "$USER_SETTINGS"; then
        pass "declared process provider '$declared' is installed"
    else
        warn "CLAUDE.md declares '$declared' as this project's process provider, but it is not"
        warn "  installed for this user. Kinglet's built-in discovery surface (/unity-interview)"
        warn "  is the fallback. Re-run install.sh to refresh the declaration, or delete the"
        warn "  'Process provider' section from CLAUDE.md."
    fi
fi
```

- [ ] **Step 4: Run to verify it passes**

Run the same runner-scoped command as Step 2 — the three new assertions now PASS.
Then the full gate set:

```bash
bash tests/run-tests.sh 2>&1 | tail -4
bash scripts/check-provenance.sh 2>&1 | tail -3
bash tests/run-tests.sh 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -c -- "--- test-.*\.sh ---"
ls tests/test-*.sh | wc -l
```

Expected: `Failed: 0`; `provenance OK`; last two numbers equal.

- [ ] **Step 5: Commit**

```bash
git add scripts/studio-doctor.sh tests/test-studio-doctor.sh
git commit -m "feat(studio-doctor): warn when a declared process provider is gone

The platform design's 'if the active provider later disappears, doctor offers
the built-in provider as an explicit fallback', made concrete.

A warning, never a failure. The project still works; the declaration is just no
longer true, and studio-doctor exits 1 only on fail."
```

---

## What this plan does not do

| Deferred | To | Why |
|---|---|---|
| The trigger-description rewrite (Wave 1b-2 Tasks 3-5) | Behind two gates | The design spec names both: decision (2) shipped — Task 3 here — **and** the invocation measurement re-run with the `Agent` tool present. Task 3's commit message says `description:` is deliberately untouched; keep it that way. |
| Enforcement blocks (`HARD-GATE`, checklist→todo, red-flag tables) | Behind Task 1 shipping | Enforcement multiplies the content it wraps, and the content is wrong for real projects until Task 1 exists. |
| A `superpowers` origin in `provenance.tsv` | Wave 2 | No file in this plan derives from Superpowers. Widening the origin enum in `check-provenance.sh:103` with no rows to use it is dead code. |
| Cutting the 103-surface pool | A separate decision | Recorded as an open question in the design spec, informed by the same corrected measurement. |
| The A/B proving the corrected sentence changes behaviour | After Task 2 | Success criterion 3 in the spec. It is the honest proof and it is not a code change; run it by field note 87's method and write the result — whatever it is — into `field-notes.md`. |

## Self-review

**Spec coverage.** Decision 1 (rule applicability) → Tasks 1 and 2. Decision 2 (plan as input) → Task 3. Decision 3 (provider declaration) → Tasks 4 and 5. Decision 4 (trigger amendment) → deliberately not implemented; the table above records it with its two gates. Every error-handling row in the spec has a step: unreadable manifest → Task 1 Step 4's `manifest_has` returning false; mixed evidence → the `manifest-only` state; greenfield → the `CS_FILE_COUNT -eq 0` branch; unreadable plan → Task 3 Step 4's hard stop; missing acceptance criteria and multiple matches → the same step; stale provider → Task 5; provider declined → Task 4's default-empty `PROVIDER_CHOICE`.

**One thing this plan adds that the spec did not have:** Task 2. The spec assumed the stack assertion lived only in the rules. Reading `generate-claude-md.sh:317-328` showed it is also in the static tail, outside the markers, written once and never refreshed. Without Task 2 the generated document would contradict itself permanently. This is a gap in the spec, not in the design — report it so the spec can be amended.

**Placeholder scan.** No TBD, no "add error handling", no "similar to Task N". Every code step carries the literal text to write. The two prose steps (Task 3 Step 4, Task 2 Step 3) give the full replacement text rather than describing it.

**Type consistency.** `VC_PRESENT` / `MP_PRESENT` / `UT_PRESENT` carry `yes|manifest-only|no` in Task 1 and are read with those exact values in Task 1 Step 5. `CS_FILE_COUNT`, `COROUTINE_FILES`, `VC_REFS`, `MP_REFS`, `UT_REFS` are integers throughout. `PROVIDER` is the script variable, `PROVIDER_CHOICE` the installer variable, `KINGLET_USER_SETTINGS` the override — each used consistently in Tasks 4 and 5. `emit_stack_verdict` and `emit_provider_verdict` are both called from `emit_marked_region` and never elsewhere.

**Known cost, stated rather than hidden.** Task 1's detection runs one `grep` per first-party `.cs` file. On a 1000-script project that is a thousand invocations at generation time — seconds, not minutes, and generation runs at install and on explicit refresh, not per session. The alternative (`grep -rl` with `--exclude-dir`) is a GNU extension this repo's shell conventions rule out.
