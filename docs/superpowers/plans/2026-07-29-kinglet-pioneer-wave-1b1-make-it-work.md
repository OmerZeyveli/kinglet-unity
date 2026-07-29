# Kinglet Pioneer — Wave 1b-1 (Make It Work) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close every defect that stops Kinglet Pioneer from functioning in a real Unity project, so it can be installed and used.

**Architecture:** Five tasks, each fixing a defect the smoke pass measured rather than one anybody predicted. Two of them fix a *class* and not only the instance that was caught: Stop hooks that can block a session, and a command classifier that matches unanchored substrings.

**Tech Stack:** bash 3.2-compatible shell, `jq`, the `tests/run-tests.sh` harness, `scripts/check-provenance.sh`.

## Authority

The scope of this plan comes from **`docs/research/pioneer/smoke-pass.md`** — a measured record, not a prediction. It supersedes the ordering in `docs/superpowers/specs/2026-07-29-kinglet-pioneer-design.md` §Wave 1b, which was written before anything had been run.

Wave 1b is split into three plans because the work divides cleanly and the first one is what unblocks use:

| Plan | Deliverable |
|---|---|
| **1b-1 — make it work** (this plan) | Pioneer installs into a Unity project and functions. Defects 1, 2, 4, 5, 6, 7, 8, 9. |
| **1b-2 — make it findable** | The command/skill surface is machine-selectable. Defect 3, ~75 files, its own plan because it is one large mechanical change with one test. |
| **1b-3 — make it durable** | Durable artifacts, the design↔engineering link, the code map. The original spec items, deferred behind the two above because a toolkit that hangs and cannot see the Editor has bigger problems than forgetting its plans. |

## Global Constraints

- **Bash 3.2 (macOS) compatible.** No `declare -A`. No `grep -oP`, no `grep -qP` — GNU-only.
- **Never pipe into `head`** under `set -euo pipefail`. Use `awk`.
- **Validate an argument before `shift 2`** — `shift` fails under `set -u` before the error prints.
- **`bash tests/run-tests.sh` must pass at every commit, with every test file present in its output.** Count the files; this runner has reported green while running one of eight.
- **`scripts/check-provenance.sh` must report `provenance OK`** at every commit. New tracked files need a row (`original` / `original`).
- **Editing a vendored file flips its `status` to `modified`** in `provenance.tsv`, with a reason in the `note` column, in the same commit. Most hooks here are already `modified`; check, don't assume.
- **Never silently mutate a user's Unity project.** Anything that writes into `Packages/manifest.json` or the project root is either behind an explicit flag or announced and skippable. The installer's existing `--with-mcp` is the pattern to follow.

---

### Task 1: An advisory hook must not be able to block a session

**Defect 1 (Critical).** Installing Pioneer into a Unity project that is not a git repository hangs every Claude Code session in it. Root cause in `smoke-pass.md` §2; the short version is that `session-save.sh` builds invalid JSON, `jq` fails, `set -e` exits the hook non-zero, and **a `Stop` hook exiting non-zero blocks the stop** and feeds its stderr back as a reason to continue.

Fix the class, then the instance.

**Files:**
- Modify: `.claude/hooks/_lib.sh` — add the advisory-exit guard
- Modify: `.claude/hooks/session-save.sh` — adopt the guard; fix `RECENT_COMMITS`
- Modify: `.claude/hooks/auto-learn.sh`, `instinct-distill.sh`, `notify.sh`, `stop-validate.sh` — adopt the guard
- Modify: `.claude/hooks/notify.sh:243` — the same pipeline shape
- Test: `tests/test-hook-advisory-exit.sh` (create)
- Modify: `provenance.tsv`

**Interfaces:**
- Consumes: nothing.
- Produces: a shell function `advisory_exit_guard` in `_lib.sh` that later hooks may adopt.

- [ ] **Step 1: Write the failing test**

Create `tests/test-hook-advisory-exit.sh`:

```bash
#!/usr/bin/env bash
# ============================================================================
# test-hook-advisory-exit.sh — Stop hooks must never block the stop.
#
# A Stop hook that exits non-zero does not merely fail: Claude Code treats it
# as a refusal, feeds its stderr back to the model as a reason to keep going,
# and the session never terminates. Every Stop hook in this payload is
# advisory, so every one of them must exit 0 no matter what it hits.
#
# The regression this pins: with no git repository, session-save.sh built
# invalid JSON, jq failed, set -e propagated, and the hook exited 2.
# ============================================================================

HAE_TMP="/tmp/kinglet-advisory-$$"
HAE_HOOKS="${REPO_DIR}/.claude/hooks"
HAE_PAYLOAD='{"session_id":"t","hook_event_name":"Stop","cwd":"'"$HAE_TMP"'"}'

mkdir -p "$HAE_TMP"

# A directory that is emphatically not a git repository, and not inside one.
cd "$HAE_TMP" || exit 1

for hae_hook in session-save auto-learn instinct-distill notify stop-validate; do
    hae_out=$(printf '%s' "$HAE_PAYLOAD" \
        | bash "${HAE_HOOKS}/${hae_hook}.sh" 2>&1)
    hae_rc=$?
    assert_eq "0" "$hae_rc" "${hae_hook}.sh exits 0 outside a git repository"
    # A hook that "succeeds" by printing a jq parse error has not succeeded.
    assert_not_contains "$hae_out" "invalid JSON" \
        "${hae_hook}.sh produces no jq parse error outside a git repository"
done

# The same, inside a git repository, so the fix is not "always bail out early".
mkdir -p "${HAE_TMP}/repo" && cd "${HAE_TMP}/repo" || exit 1
git init -q
git config user.email "t@example.invalid"
git config user.name "t"
printf 'x\n' > a.txt
git add a.txt
git commit -qm "seed"

hae_out=$(printf '{"session_id":"t","hook_event_name":"Stop","cwd":"'"${HAE_TMP}/repo"'"}' \
    | bash "${HAE_HOOKS}/session-save.sh" 2>&1)
hae_rc=$?
assert_eq "0" "$hae_rc" "session-save.sh exits 0 inside a git repository"
assert_contains "$hae_out" "Session state saved" \
    "session-save.sh still does its job inside a git repository"

cd "$REPO_DIR" || exit 1
rm -rf "$HAE_TMP"
```

- [ ] **Step 2: Run it and watch it fail**

Run: `bash tests/run-tests.sh 2>&1 | grep -A24 'test-hook-advisory-exit'`

Expected: `session-save.sh exits 0 outside a git repository` FAILS with actual `2`, and the
`invalid JSON` assertion FAILS. The other four hooks should already pass — they were checked during
the smoke pass and exit 0. If any of them fails too, that is a second instance of the same class and
belongs in this task.

- [ ] **Step 3: Add the guard to `_lib.sh`**

Append to `.claude/hooks/_lib.sh`:

```bash
# ---------------------------------------------------------------------------
# advisory_exit_guard — for hooks whose contract is "advisory, exit 0 always".
#
# Claude Code reads a non-zero exit from a Stop hook as a refusal to stop: it
# feeds the hook's stderr back to the model as a reason to continue, and the
# session never ends. Under `set -e` any unhandled failure inside an advisory
# hook therefore turns a cosmetic bug into a hang.
#
# Call this immediately after sourcing _lib.sh in every advisory hook. It is
# deliberately blunt: whatever goes wrong below, the process exits 0.
# ---------------------------------------------------------------------------
advisory_exit_guard() {
    trap 'exit 0' EXIT
}
```

`trap ... EXIT` rather than `trap ... ERR`: `ERR` is not inherited by subshells or command
substitutions without `set -E`, and the failure that caused this defect was inside a `$(...)`.

- [ ] **Step 4: Adopt the guard in all five Stop hooks**

In each of `session-save.sh`, `auto-learn.sh`, `instinct-distill.sh`, `notify.sh`,
`stop-validate.sh`, immediately after the `source "${SCRIPT_DIR}/_lib.sh"` line:

```bash
advisory_exit_guard
```

- [ ] **Step 5: Fix the instance, and the shape that caused it**

In `session-save.sh`, replace:

```bash
RECENT_COMMITS=$(git log --oneline -3 2>/dev/null | jq -Rs 'split("\n") | map(select(length > 0))' || echo '[]')
```

with:

```bash
# Two statements, not a pipeline with a fallback. Under `set -euo pipefail` a
# failing `git log` makes the pipeline fail *after* jq has already written its
# output, so `|| echo '[]'` appends a second value instead of replacing the
# first — and `[]\n[]` is not JSON. Capturing git separately removes the race
# between "did the pipeline fail" and "did anything get written".
COMMIT_LINES=$(git log --oneline -3 2>/dev/null || true)
RECENT_COMMITS=$(printf '%s' "$COMMIT_LINES" | jq -Rs 'split("\n") | map(select(length > 0))')
```

Apply the same shape to `notify.sh:243`:

```bash
CHANNEL_COUNT=$(printf '%s' "$CHANNELS_JSON" | jq 'length' 2>/dev/null || printf '0')
```

Here the `||` is safe because `jq` writes nothing when it fails — but make it explicit and
consistent rather than leaving a reader to work that out.

- [ ] **Step 6: Sweep the rest of the class**

`grep -rnE '\|[^|]+\|\| *(echo|printf)' .claude/hooks/*.sh` finds the shape. Most instances are
`|| true`, which is harmless — the fallback contributes nothing. The dangerous form is
`… | producer || echo <value>`, where the producer may already have written before the pipeline is
declared failed.

Inspect each match. Fix only the dangerous ones, and **list every match and its verdict in the
report** — a sweep whose "no action needed" cases are invisible is indistinguishable from a sweep
that missed them.

- [ ] **Step 7: Verify and commit**

```bash
bash tests/run-tests.sh          # green; count the files
bash scripts/check-provenance.sh # provenance OK
```

Every hook file edited that is `origin=ecu` must have `status=modified` with a note. Check
`provenance.tsv` for each before committing.

```bash
git add .claude/hooks provenance.tsv tests/test-hook-advisory-exit.sh
git commit -m "fix: an advisory hook must not be able to block a session

A Stop hook exiting non-zero is read as a refusal to stop, and its stderr is
fed back to the model as a reason to continue. Under set -e any unhandled
failure inside an advisory hook therefore hangs the session rather than
logging a warning.

The instance: with no git repository, git log fails, but under pipefail the
pipeline is declared failed only after jq has already written [], so the
|| echo '[]' fallback appended a second one. []\\n[] is not JSON.

Guarded at the class, fixed at the instance, and the remaining instances of
the pipeline shape are listed with a verdict each."
```

---

### Task 2: Write the MCP configuration where Claude Code reads it

**Defect 2 (Critical).** `claude mcp list` reports no servers in a freshly installed project. Claude Code does not read `mcpServers` from `.claude/settings.json`; project-scoped servers live in `.mcp.json` at the project root. Every `unity-*` agent drives the Editor through MCP, so as installed that half of the toolkit has no tools to call. `MCP-SETUP.md` asserts the opposite.

**Defect 5 (Important).** The installer writes `#main` into `Packages/manifest.json`, so which version a user gets depends on the day they install.

**Files:**
- Modify: `install.sh` — write `.mcp.json`; pin the MCP package ref; record `.mcp.json` in the receipt
- Modify: `uninstall.sh` — remove `.mcp.json` if we wrote it and it is unchanged
- Modify: `.claude/settings.json` — remove the inert `mcpServers` key
- Modify: `MCP-SETUP.md` — correct the false claim; document the approval step
- Modify: `.claude/UPSTREAM` — record the pinned MCP ref
- Test: `tests/test-mcp-config.sh` (create)
- Modify: `provenance.tsv`

**Interfaces:**
- Consumes: `install.sh`'s existing receipt writer and its surgical `manifest.json` editor.
- Produces: a `.mcp.json` at the project root and a receipt row for it.

- [ ] **Step 1: Write the failing test**

Create `tests/test-mcp-config.sh`:

```bash
#!/usr/bin/env bash
# ============================================================================
# test-mcp-config.sh — the MCP config must land where Claude Code reads it.
#
# The toolkit shipped mcpServers inside .claude/settings.json, which Claude
# Code ignores: `claude mcp list` reported no servers in a freshly installed
# project, so every unity-* agent had no tools to call. Project-scoped MCP
# servers are configured in .mcp.json at the project root.
# ============================================================================

TMC_MOCK="/tmp/kinglet-mcp-config-$$"
mkdir -p "${TMC_MOCK}/Assets/Scripts" "${TMC_MOCK}/ProjectSettings" "${TMC_MOCK}/Packages"
printf 'm_EditorVersion: 6000.3.18f1\nm_EditorVersionWithRevision: 6000.3.18f1 (abcdef123456)\n' \
    > "${TMC_MOCK}/ProjectSettings/ProjectVersion.txt"
printf '{\n  "dependencies": {\n    "com.unity.ugui": "1.0.0"\n  }\n}\n' \
    > "${TMC_MOCK}/Packages/manifest.json"

bash "${REPO_DIR}/install.sh" --project-dir "$TMC_MOCK" > /dev/null 2>&1 || true

assert_file_exists "${TMC_MOCK}/.mcp.json" "install writes .mcp.json at the project root"

TMC_JSON=$(cat "${TMC_MOCK}/.mcp.json" 2>/dev/null || echo "")
assert_contains "$TMC_JSON" "unityMCP" ".mcp.json names the unityMCP server"
assert_contains "$TMC_JSON" "localhost:8080/mcp" ".mcp.json carries the bridge URL"

# The inert key must be gone, or a reader will believe it does something.
TMC_SETTINGS=$(cat "${TMC_MOCK}/.claude/settings.json" 2>/dev/null || echo "")
assert_not_contains "$TMC_SETTINGS" "mcpServers" \
    "settings.json no longer carries an mcpServers key Claude Code ignores"

# The receipt must own it, or uninstall cannot remove it.
TMC_RECEIPT=$(cat "${TMC_MOCK}/.claude/state/install-receipt.tsv" 2>/dev/null || echo "")
assert_contains "$TMC_RECEIPT" ".mcp.json" "the receipt records .mcp.json"

# An existing .mcp.json belongs to the user and is not overwritten.
rm -rf "$TMC_MOCK/.claude" "$TMC_MOCK/.mcp.json"
printf '{"mcpServers":{"mine":{"type":"http","url":"http://localhost:9999/mcp"}}}\n' \
    > "${TMC_MOCK}/.mcp.json"
bash "${REPO_DIR}/install.sh" --project-dir "$TMC_MOCK" > /dev/null 2>&1 || true
TMC_EXISTING=$(cat "${TMC_MOCK}/.mcp.json")
assert_contains "$TMC_EXISTING" "localhost:9999" "an existing .mcp.json keeps the user's server"

rm -rf "$TMC_MOCK"
```

- [ ] **Step 2: Run it and watch it fail**

Run: `bash tests/run-tests.sh 2>&1 | grep -A18 'test-mcp-config'`

Expected: `install writes .mcp.json at the project root` fails first. Confirm it fails because the
file is absent, not because the install itself errored.

- [ ] **Step 3: Write `.mcp.json` from the installer**

In `install.sh`, after the payload is copied and before the receipt is written, add a step that
writes:

```json
{
  "mcpServers": {
    "unityMCP": {
      "type": "http",
      "url": "http://localhost:8080/mcp"
    }
  }
}
```

Rules, matching how the installer already treats `CLAUDE.md` and `manifest.json`:

- **If `.mcp.json` does not exist:** write it, and add it to the receipt so `uninstall.sh` can
  remove it when it is unchanged.
- **If `.mcp.json` exists and has no `unityMCP` key:** do not rewrite the file. Announce it and print
  the exact block for the user to add. Merging JSON with `sed` is how a user's config gets
  destroyed, and this installer's whole design is to not do that.
- **If `.mcp.json` exists and already has `unityMCP`:** say so and change nothing.

- [ ] **Step 4: Remove the inert key**

Delete the `mcpServers` block from `.claude/settings.json`. Leaving it costs nothing at runtime and
misleads every future reader into thinking it is load-bearing — which is exactly the belief that
produced this defect.

- [ ] **Step 5: Pin the MCP package**

`install.sh --with-mcp` currently writes a `#main` ref. Replace it with the pinned ref recorded in
`.claude/UPSTREAM`, and record in `.claude/UPSTREAM` both the pin and what the smoke pass actually
ran:

```
unity_mcp_ref=<pinned tag or commit>
unity_mcp_smoke_pass_commit=a4c2d0a84573
```

The smoke pass ran `a4c2d0a84573` from `#main`. Pioneer pins what it ran against, so unless there is
a reason to prefer a tag, pin that commit and say so.

- [ ] **Step 6: Correct `MCP-SETUP.md`**

Three changes, all load-bearing:

1. Delete the claim that there is nothing to write in `settings.json` because the toolkit ships it
   preconfigured. Replace it with what actually happens: the installer writes `.mcp.json`.
2. Document the **one-time approval**. Project-scoped MCP servers show as `⏸ Pending approval` until
   the user approves them in an interactive session. Adding `enabledMcpjsonServers` to
   `.claude/settings.json` did **not** clear it in the version tested; say that plainly rather than
   recommending something unverified.
3. Add the headless bridge recipe from `smoke-pass.md` §6 — `UNITY_MCP_ALLOW_BATCH=1`,
   `StartLocalHttpServer(quiet: true)`, **wait for the port**, then `Bridge.StartAsync()` — and the
   `-nographics` crash on real URP scenes. Both cost hours to rediscover.

- [ ] **Step 7: Teach `uninstall.sh` about `.mcp.json`**

It is receipt-driven, so once `.mcp.json` is in the receipt with its checksum, the existing logic
removes it when unchanged and leaves it when the user edited it. Verify this rather than assuming —
add an assertion to the test that a modified `.mcp.json` survives uninstall.

- [ ] **Step 8: Verify and commit**

```bash
bash tests/run-tests.sh
bash scripts/check-provenance.sh
```

```bash
git add install.sh uninstall.sh .claude/settings.json .claude/UPSTREAM MCP-SETUP.md \
        tests/test-mcp-config.sh provenance.tsv
git commit -m "fix: write the MCP config where Claude Code actually reads it

claude mcp list reported no servers in a freshly installed project. The
toolkit put mcpServers in .claude/settings.json, which Claude Code ignores;
project-scoped servers live in .mcp.json at the project root. Every unity-*
agent drives the Editor through MCP, so that half of the toolkit had no tools
to call, while MCP-SETUP.md said it was preconfigured.

The inert key is removed rather than left in place, because leaving it is what
convinced everyone it worked.

An existing .mcp.json is never rewritten — the installer prints the block and
lets the user merge it, the same way it refuses to reformat a manifest."
```

---

### Task 3: The New Input System is mandatory, so say so at install time

**Defect 4 (Important).** `unity-specifics.md` makes the New Input System non-negotiable and a hook blocks the legacy API, but nothing checks that `com.unity.inputsystem` is present. In the smoke pass the first script written under the project's own rules failed to compile — and a compile failure also aborts `-executeMethod`, so it blocks Editor automation entirely.

**Do not silently add the package.** The installer's contract is that it does not mutate a user's project without a flag. Detect, announce, and offer.

**Files:**
- Modify: `install.sh` — detect and report; add `--with-input-system`
- Modify: `scripts/studio-doctor.sh` — report it in the health check
- Test: `tests/test-input-system-check.sh` (create)
- Modify: `provenance.tsv`

**Interfaces:**
- Consumes: the manifest reader `install.sh` already uses for `--with-mcp`.
- Produces: a `--with-input-system` flag with the same semantics as `--with-mcp`.

- [ ] **Step 1: Write the failing test**

```bash
#!/usr/bin/env bash
# ============================================================================
# test-input-system-check.sh — the mandated input package must be checked for.
#
# unity-specifics.md makes the New Input System non-negotiable and a hook
# blocks the legacy API. A project without com.unity.inputsystem therefore
# cannot compile the first script written under its own rules — and a compile
# error also aborts Unity's -executeMethod, so Editor automation stops too.
# ============================================================================

TIS_MOCK="/tmp/kinglet-input-check-$$"
mkdir -p "${TIS_MOCK}/Assets" "${TIS_MOCK}/ProjectSettings" "${TIS_MOCK}/Packages"
printf 'm_EditorVersion: 6000.3.18f1\nm_EditorVersionWithRevision: 6000.3.18f1 (abcdef123456)\n' \
    > "${TIS_MOCK}/ProjectSettings/ProjectVersion.txt"
printf '{\n  "dependencies": {\n    "com.unity.ugui": "1.0.0"\n  }\n}\n' \
    > "${TIS_MOCK}/Packages/manifest.json"

TIS_OUT=$(bash "${REPO_DIR}/install.sh" --project-dir "$TIS_MOCK" 2>&1 || true)
assert_contains "$TIS_OUT" "com.unity.inputsystem" \
    "install warns when the mandated input package is absent"

# Present: no warning, because a warning nobody needs is a warning nobody reads.
rm -rf "${TIS_MOCK}/.claude"
printf '{\n  "dependencies": {\n    "com.unity.inputsystem": "1.18.0"\n  }\n}\n' \
    > "${TIS_MOCK}/Packages/manifest.json"
TIS_OUT2=$(bash "${REPO_DIR}/install.sh" --project-dir "$TIS_MOCK" 2>&1 || true)
assert_not_contains "$TIS_OUT2" "com.unity.inputsystem is missing" \
    "install stays quiet when the input package is already present"

rm -rf "$TIS_MOCK"
```

- [ ] **Step 2: Run it and watch it fail.** Expected: the warning assertion fails; nothing mentions the package.

- [ ] **Step 3: Implement detection, warning, and the flag.** Follow `--with-mcp` exactly: same manifest-editing helper, same backup behaviour, same "could not edit safely" fallback that prints the line for the user.

- [ ] **Step 4: Add it to `studio-doctor.sh`**, so an already-installed project can find out too.

- [ ] **Step 5: Verify and commit.**

---

### Task 4: The classifier must match commands, not strings that look like commands

**Defect 6 (Important).** `bash-gate.sh` blocked a command that wrote nothing, because `ProjectSettings/ProjectSettings.asset` appeared inside a JSON argument. Line 62 is `(rm|>|mv|cp)\s+.*ProjectSettings/[A-Za-z]+\.asset` — the `.*` between the verb and the path lets any text intervene.

**Defect 7 (Minor).** The gate's message says *"retry the same command — it will pass"*, but the key is a hash of the whole command string including unrelated lines in the same invocation. A retry that reformats anything is a different command and is blocked again. Measured: a byte-identical retry passes; a semantically identical one does not.

A false block costs more than a missed one — it argues with the developer every day, and the arguing is what trains people to disable the gate.

**Files:**
- Modify: `.claude/hooks/bash-gate.sh` — tighten the patterns; correct the message
- Test: `tests/test-bash-gate-precision.sh` (create)
- Modify: `provenance.tsv`

- [ ] **Step 1: Write the failing test**

```bash
#!/usr/bin/env bash
# ============================================================================
# test-bash-gate-precision.sh — the gate must classify commands, not text.
#
# A false block costs more than a missed one: it argues with the developer
# every day, and that is what gets a gate disabled. Measured case — a command
# that wrote nothing was classified projectsettings-write because the path
# appeared inside a JSON argument.
# ============================================================================

TBG_HOOK="${REPO_DIR}/.claude/hooks/bash-gate.sh"

tbg_run() {
    printf '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":%s}}' \
        "$(printf '%s' "$1" | jq -Rs .)" | bash "$TBG_HOOK" > /dev/null 2>&1
    printf '%s' "$?"
}

# Must still block — these really do write.
assert_eq "2" "$(tbg_run 'echo hi > ProjectSettings/ProjectSettings.asset')" \
    "still blocks a real redirect into ProjectSettings"
assert_eq "2" "$(tbg_run 'rm -f Assets/Player.cs.meta')" \
    "still blocks a real .meta deletion"

# Must not block — the path is data, not a target.
assert_eq "0" "$(tbg_run 'grep -n ProjectSettings/ProjectSettings.asset notes.txt')" \
    "does not block a grep that merely names ProjectSettings"
assert_eq "0" "$(tbg_run 'echo "see ProjectSettings/ProjectSettings.asset for details"')" \
    "does not block an echo that merely mentions the path"
assert_eq "0" "$(tbg_run 'git log -- Assets/Player.cs.meta')" \
    "does not block reading history of a .meta file"
```

- [ ] **Step 2: Run it and watch it fail.** Expected: the three "does not block" assertions fail with `2`. The two "still blocks" assertions should already pass — if either fails, stop: the fix must not weaken real coverage, and knowing they passed *before* is what proves it didn't.

- [ ] **Step 3: Tighten the patterns.** For each classification, the target must be an argument of the destructive verb, not any text on the line. Anchor the verb to a command position (start of line, or after `;`, `&&`, `||`, or a pipe) and remove the permissive `.*` between verb and path. Keep `grep -qE` — no `-P`.

- [ ] **Step 4: Correct the retry message.** It must say what "the same command" means: byte-identical, including every other line in the same invocation. Better still, print the key it recorded so a caller can tell whether their retry will match.

- [ ] **Step 5: Verify and commit.**

---

### Task 5: Installer and uninstaller housekeeping

Two small measured defects. Together they are one commit.

**Defect 8 (Minor).** `uninstall.sh` writes `.claude.backup.<timestamp>/`, which no `.gitignore` entry the installer adds will match, so it appears as untracked and dirties the user's `git status`.

**Defect 9 (Minor).** The installer's "Next steps" told the user to fill `FILL:` markers in `CLAUDE.md` in the very run where it had deliberately **not** written `CLAUDE.md` — the markers were in `CLAUDE.md.generated`, which the message never mentioned.

**Files:**
- Modify: `install.sh` — add `.claude.backup.*/` to the `.gitignore` entries; make the next-steps text follow the branch actually taken
- Test: extend `tests/test-install.sh`
- Modify: `provenance.tsv`

- [ ] **Step 1: Write the failing assertions** in `tests/test-install.sh`: after an install into a mock project that already has a `CLAUDE.md`, the output must name `CLAUDE.md.generated` and must not tell the user to edit `CLAUDE.md`; and `.gitignore` must contain a pattern matching `.claude.backup.20260101120000/`.

- [ ] **Step 2: Run and watch both fail.**

- [ ] **Step 3: Implement.** The installer already knows which `CLAUDE.md` branch it took — that variable decides the message rather than a fixed string.

- [ ] **Step 4: Verify and commit.**

---

### Task 6: The health check must not stop halfway and call it success

**Added 2026-07-29, after Task 3, from a controller-confirmed defect.** Task 3's implementer reported
a symptom; the diagnosis and the cause below are the controller's, verified directly.

**Measured, on a freshly installed project:**

```
$ bash scripts/studio-doctor.sh --project-dir /tmp/fixture
Kinglet Pioneer — studio-doctor
Project: /tmp/fixture
Installed: Kinglet Pioneer 3.0.0-pioneer.1 (vendored ECU 1.5.0)

PASS Python 3.13 (3.10+ required)
PASS uv present (uv 0.11.32)
$ echo $?
0
```

Two checks, then silence, then **exit 0**. The MCP bridge check, the `.claude/` integrity check, the
hook-reference check and the summary line never run. A health check that reports a fraction of its
checks and exits successfully does not merely fail — it **certifies a project it never examined**.

**Root cause.** `read_mcp_url()` ends with a `for` loop whose body returns on success. When nothing
matches, the loop falls through and the function's exit status is that of its last command — a false
`[ -n "$url" ] && { … }` — so it returns 1. `MCP_URL=$(read_mcp_url)` then fails under `set -e` and
kills the script. There is no explicit `return 0`.

**Why it appeared now.** The bug was latent for as long as the URL was always found. Task 2 removed
`mcpServers` from `.claude/settings.json` — correctly, because Claude Code never read it — and
`read_mcp_url` looks **only** at `settings.local.json` and `settings.json`. It does not know
`.mcp.json` exists. So the lookup now always fails, and the latent bug fires on every run.

Neither task was wrong in isolation. This is the failure that only appears where they meet, which is
why a task-scoped review could not have caught it.

**Files:**
- Modify: `scripts/studio-doctor.sh` — `read_mcp_url` returns 0 explicitly and reads `.mcp.json`; audit the whole script for other early exits
- Test: `tests/test-studio-doctor.sh` (create)
- Modify: `provenance.tsv`

- [ ] **Step 1: Write the failing test**

Assert against a real fixture (`bash tests/fixtures/mkproject.sh <dir> --variant urp`, then install):

- `studio-doctor.sh` **reaches its summary line** — the output contains `passed ·` and the warning/failure counts.
- It reports on the MCP bridge rather than skipping it, now that `.mcp.json` is where the URL lives.
- It exits 0 on a healthy project **and** non-zero when a check genuinely fails — the second half matters, because "always exit 0" would pass the first assertion while being a worse bug than the one being fixed.
- A **direct** assertion on the cause: `read_mcp_url` returns 0 when it finds nothing. Call it in a subshell with no config present and check `$?`. Without this, the next refactor reintroduces the same fall-through and only the indirect assertions catch it, three steps downstream.

- [ ] **Step 2: Run it and watch it fail.** Expected: the summary-line assertion fails because the script died after two checks. Confirm that is the reason, not a fixture problem.

- [ ] **Step 3: Fix `read_mcp_url`.** Add an explicit `return 0`, and teach it to read `.mcp.json` at the project root — `mcpServers.unityMCP.url`, the same shape `install.sh` now writes — before falling back to the settings files. Preserve the existing precedence comment's intent: a machine-local override still wins.

- [ ] **Step 4: Audit the rest of the script for the same shape.** Any function whose last statement is a conditional, assigned through `$(...)` under `set -e`, is the same defect waiting. **List every function you checked and its verdict in the report** — a sweep whose clean cases are invisible cannot be told apart from one that missed them.

- [ ] **Step 5: Verify and commit.** `bash tests/run-tests.sh` green with every file present; `scripts/check-provenance.sh` OK; regenerate the baseline in a separate commit if `.claude/` drifted.

### Task 7: The suite fails under concurrency, and the reproduction is deterministic

**Added 2026-07-29, after Task 5.** Three implementers independently reported a flake in this suite,
each under a concurrent run, none reproducible in isolation. Three independent reports is a signal.
The controller reproduced it deterministically; the hard part is done, and this task is to explain
and fix it.

**Reproduction — fails every time:**

```bash
( bash tests/run-tests.sh > /tmp/a.txt 2>&1 ) &
( bash tests/run-tests.sh > /tmp/b.txt 2>&1 ) &
wait
```

Both runs fail. Run either alone and it passes.

**What was already narrowed:**

| Observation | What it rules out |
|---|---|
| Two concurrent copies of `tests/test-pioneer-identity.sh` **alone** both pass | The collision is not within that file — it is **cross-file** |
| The scratch dir is `mktemp -d`, not PID-keyed | Not the scratch directory |

**The clue, and it is a strange one.** Three assertions read the same receipt. Two fail, one passes:

```
FAIL receipt header is brand-level      needle: # kinglet install receipt
PASS receipt records the edition as data      (needle: # edition: pioneer)
FAIL receipt stamps the version         needle: # toolkit-version: 3.0.0-pioneer.1
```

`install.sh` writes those three lines consecutively — `# kinglet install receipt`, then
`# edition: pioneer`, then the version. **A receipt containing the second but not the first or third
is not a truncation and not a missing file.** Whatever explains that asymmetry is the defect.

Do not stop at "it is a race, so isolate the directory". An isolation fix that makes the symptom go
away without explaining the asymmetry leaves the real cause in place, and the next concurrent run
finds it again somewhere else.

**Files:** `tests/test-pioneer-identity.sh`, and whatever the investigation implicates. Likely
suspects to check rather than assume: `install.sh`'s payload enumeration reads the repository's own
`.claude/` tree while another test may be writing under it; `.claude/hooks/_lib.sh` resolves
`UNITY_HOOK_STATE_DIR` to a machine-global path when unset; several test files key scratch paths on
`$$`, which under this runner is the **runner's** PID, shared by every file in that run.

- [ ] **Step 1: Explain the asymmetry before changing anything.** Instrument the test to dump the
  receipt's actual bytes when an assertion fails, run the concurrent reproduction, and put the real
  content in the report. Everything after this depends on knowing what was actually in the file.

- [ ] **Step 2: Name the two files that collide.** Bisect by running the identity test concurrently
  with one other test file at a time. Report the pair and the shared resource.

- [ ] **Step 3: Write a failing test.** It must fail on the current tree under the concurrent
  reproduction and pass after the fix. If the cause cannot be expressed as a test, say so and explain
  why rather than shipping a fix with no net.

- [ ] **Step 4: Fix the cause, not the symptom.** State plainly which you fixed. If the honest answer
  is that the suite is not safe to run concurrently and should declare that rather than pretend
  otherwise, that is an acceptable outcome — but it must be a written decision, not a silence.

- [ ] **Step 5: Verify.** The concurrent reproduction passes twice in a row; `bash tests/run-tests.sh`
  green with every file present; `scripts/check-provenance.sh` OK.

### Task 8: Two documents still send the reader to the file Claude Code never reads

**Added 2026-07-29, from Task 6's review.** Task 2 moved MCP configuration to `.mcp.json`; Task 6
found `studio-doctor.sh` still looking in the old place, twice. The reviewer then found a third
instance, and a sweep of the payload and docs found a fourth.

Four references remain. **Two are stale instructions and must be fixed:**

| File | Says |
|---|---|
| `.claude/commands/unity-doctor.md:19` | *"Check `.claude/settings.json` → `mcpServers.unityMCP.url`"* — this **ships to users** and tells their agent to diagnose the bridge by reading a key that no longer exists |
| `docs/GETTING-STARTED.md:173` | *"Ensure `settings.json` has the correct `mcpServers` block"* — troubleshooting advice that cannot work |

**Two are legitimate and must be left alone:**

| File | Why it stays |
|---|---|
| `scripts/studio-doctor.sh:85` | A comment recording *why* settings.json is only a last-resort fallback — history, not instruction |
| `MCP-SETUP.md:120` | Explains why `settings.local.json` fails for the same reason — explanation, not instruction |

The distinction is the whole task: **prose that tells someone to do something must be true; prose that
records why something is the way it is must stay.** A sweep that deletes both kinds destroys the
record that explains the fix.

- [ ] **Step 1:** Correct `.claude/commands/unity-doctor.md` to name `.mcp.json` and the key path that exists there. This is payload — it lands in a user's project, so it must match what `install.sh` writes.
- [ ] **Step 2:** Correct `docs/GETTING-STARTED.md`'s troubleshooting step likewise.
- [ ] **Step 3:** Add a test asserting no *instruction* in `.claude/` tells a reader to find MCP configuration in `settings.json`. Scope it so the two legitimate explanatory comments do not fail it — if that cannot be expressed cleanly, say so and record the exclusion by exact path with its reason, the way the identity guard does.
- [ ] **Step 4:** `.claude/` changed, so regenerate the baseline in a separate commit. Verify the suite and provenance.

### Task 9: Sweep the early-exit pipe shape out of the rest of the tree

**Added 2026-07-29, from Task 7.** Task 7 found that `echo "$haystack" | grep -qF "$needle"` in the
assertion helpers reported failures that never happened: `grep -q` exits on first match without
draining stdin, a haystack over `PIPE_BUF` cannot be written atomically, and the inherited
`set -euo pipefail` turned the writer's SIGPIPE into a failed assertion.

`grep -rn '| *grep -q' scripts/*.sh tests/*.sh` finds **39 occurrences across 12 files**:
`scripts/{studio-doctor,validate-asmdefs,validate-architecture,validate-code-quality,validate-serialization,detect-missing-refs,analyze-build-size}.sh`,
`tests/{run-tests,test-cross-validation,test-state,test-skills,test-assert-helpers-under-load}.sh`.

**Most of them are fine, and that is the point of the task.** The shape is only dangerous when the
left-hand side can produce more than a pipe buffer holds. `printf '%s' "$one_line" | grep -q …` is
harmless; `find … | grep -q …` over a large tree is not. A sweep that rewrites all 39 is churn that
hides the handful that matter.

- [ ] **Step 1: Classify all 39 with a verdict each**, in a table in the report: file, line, what the writer produces, bounded or unbounded, verdict. Unreported clean cases are indistinguishable from missed ones.
- [ ] **Step 2: Fix only the unbounded ones**, with a here-string or a form with no pipe.
- [ ] **Step 3: Prove at least one.** Pick the worst case, reproduce a false result under contention the way Task 7 did, then show it fixed. A sweep with no reproduction is a guess with a table attached.
- [ ] **Step 4:** Suite green with every file present; `check-provenance.sh` OK; `verbatim` rows flipped where edited; baseline regenerated in a separate commit if `.claude/` drifted.

## What this plan does not do

| Deferred | To | Why |
|---|---|---|
| Machine-selectable surface descriptions | Wave 1b-2 | ~75 files, one mechanical change, one test — a plan of its own |
| Durable artifacts, design↔engineering link, code map | Wave 1b-3 | Real value, but a toolkit that hangs and cannot see the Editor has bigger problems |
| The `/unity-skill-stocktake` measurement | The interactive pass | Named in `smoke-pass.md` §8 |
| `superpowers` as a `provenance.tsv` origin | Wave 2 | Still no adapted file to describe |

## Self-review

**Spec coverage.** Every defect in `smoke-pass.md`'s list is either a task here (1, 2, 4, 5, 6, 7, 8, 9) or explicitly deferred with a destination (3, 10). Defect 10 — the generated `CLAUDE.md` reading as though its rule listing is what loads them — is folded into Task 2's documentation work, since that file is being edited there anyway; if it is not, it moves to 1b-3.

**Placeholder scan.** No TBD. Every test body is written out. Task 3, 4 and 5's implementation steps describe the change rather than pasting final code, because each follows an existing pattern in the same file (`--with-mcp`, the sibling classifiers, the existing branch variable) and pasting a guess at that code would be less accurate than pointing at the pattern.

**Type consistency.** `advisory_exit_guard` is defined in `_lib.sh` in Task 1 Step 3 and called by the same name in Step 4 and in the test. `.mcp.json`'s shape is identical in Task 2's test, Step 3, and `MCP-SETUP.md`. `--with-input-system` is named the same in Task 3's steps and in its test.
