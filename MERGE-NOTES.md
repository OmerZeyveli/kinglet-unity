# Merge Notes (developer record)

How Kinglet Pioneer (assembled and first shipped as `cloud-nine-unity`, then renamed) was put
together: what was taken from where, what was adapted, what was deliberately left out, and which
calls/assumptions were mine. This is a build record for maintainers — end users want `README.md`.

It has two parts, because the project was built twice:

- **Part 1 — the overlay build.** cloud-nine-unity as an *add-on* to ECU: you installed ECU, then
  installed this on top. The Donchitos adaptation work below all dates from here and is unchanged.
- **Part 2 — the standalone merge.** ECU vendored into this repo, one installer, mobile stripped,
  upstream defects fixed. This is what ships now, and it inverts several Part 1 decisions.

Where the two disagree, **Part 2 wins**. Part 1 is kept because the *reasoning* behind the design
layer is still the reasoning, and because a build record that quietly deletes its own history isn't
one.

## Source projects (all MIT)

| Project | Version / commit basis | Role |
|---------|------------------------|------|
| everything-claude-unity (ECU) | **v1.5.0** (`bb28ccb`) | Engineering layer. **Vendored** — see Part 2. (Upstream's `plugin.json` is stale at 1.3.0 with old counts 22/41; `.claude/VERSION` was the reliable read.) |
| Claude-Code-Game-Studios (Donchitos) | **`984023d`** | Source of the adapted design/production layer. |
| unity-mcp (CoplayDev) | package `com.coplaydev.unity-mcp` **10.1.0** (2026-07-13) | MCP bridge targeted by docs/automation — **not vendored**; `settings.json` used to point at it on localhost. That moved to `.mcp.json`. |

Pins of record live in `.claude/UPSTREAM`; per-file truth lives in `provenance.tsv`.

---

# Part 1 — the overlay build

## Taken from Donchitos and adapted

- **8 agents:** `game-designer`, `systems-designer`, `level-designer`, `narrative-director`,
  `writer`, `world-builder`, `creative-director`, `technical-director`.
- **9 commands** (Donchitos calls them "skills" and ships them as `skills/<name>/SKILL.md`; they
  install here as `.claude/commands/<name>.md`): `brainstorm`, `design-review`, `map-systems`,
  `design-system`, `sprint-plan`, `scope-check`, `milestone-review`, `estimate`, `retrospective`.
- **5 templates:** `game-design-document`, `architecture-decision-record`, `sprint-plan`,
  `game-concept`, `systems-index`.

Every adapted file carries an inline `<!-- Adapted from Claude-Code-Game-Studios (Donchitos), MIT -->`
comment, in addition to the central `CREDITS.md` attribution and its `provenance.tsv` row.

## Format delta applied (Donchitos → ECU conventions)

Verified field-by-field against real ECU files (`agents/unity-reviewer.md`, `commands/unity-review.md`),
not an assumed schema:

- **Agents.** Donchitos frontmatter carried `maxTurns`, `disallowedTools`, `memory`, and a `skills: []`
  array. **Removed** those; **added** ECU's `color`; reduced `tools` to a doc-layer set
  (`Read, Write, Edit, Glob, Grep`, plus `WebSearch` for the designer/narrative/director roles).
  Crucially, **none of these agents get `mcp__unityMCP__*` tools or write C#** — they are a
  documentation/design layer. The `unity-*` coder agents own implementation.
- **Commands.** Donchitos skill frontmatter (`argument-hint`, `allowed-tools`, `model`, sometimes a
  `context:` bash preamble) was reduced to ECU's command frontmatter (`name`, `description`,
  `user-invocable`, `args`). Model/agent routing moved into the body, mirroring `unity-review`.
- **Rules.** `pc-console.md` is plain Markdown with **no frontmatter**, matching the other rule files.
- **Paths.** Repointed Donchitos's `design/gdd/` → `docs/design/`, `production/*` → `docs/production/*`,
  `docs/architecture/adr-*` → `docs/adr/`, and `assets/data/` → ScriptableObjects / external config.

## Process weight: trimmed to MEDIUM

Donchitos runs a heavy multi-gate pipeline. I cut it to keep the toolkit solo-friendly:

- **Removed** the `--review full|lean|solo` mode machinery, the `production/review-mode.txt` file,
  and all references to `.claude/docs/director-gates.md` and named gates (`CD-PILLARS`,
  `TD-FEASIBILITY`, `PR-SPRINT`, etc.).
- **Removed** the mandatory `producer` / `art-director` gate spawns. Where a senior check still adds
  value, the command now **optionally** spawns `creative-director` or `technical-director` for a
  verdict (APPROVE/CONCERNS/REJECT) — explicitly "not a gate, skip for a fast solo pass."
- **Kept** the collaborative, section-by-section authoring flow (skeleton → discuss → approve →
  write) because that is the genuinely valuable part and is light enough for solo use.

## Left out (and why)

- **Agents:** `producer` (heavy cross-domain coordination), `live-ops-designer`, `community-manager`,
  `localization-lead`, `economy-designer` (folded into `systems-designer`), `analytics-engineer` —
  post-launch / live-ops / heavy-coordination roles outside a medium-weight, pre-launch solo scope.
- **The full GDD gate pipeline** and the global review-mode system (see above).
- **Donchitos's engine-agnostic code rules** (`coding-standards.md`, `technical-preferences.md`,
  `coordination-rules.md`, `context-management.md`). These overlap with ECU's rules and would
  conflict (Donchitos is Godot/Unity/Unreal-generic; ECU is opinionated Unity). **The ECU rules
  win** — I did not bring these over.
- Donchitos's many extra templates (art bible, economy model, UX spec, etc.) — out of scope for a
  PC/console design+production toolkit; can be added later if needed.

## PC/console adaptation (as it stood in Part 1)

- Added a single new rule, `pc-console.md`, at a new path with no collision with the 5 ECU rules. In
  Part 1 it worked as a **corrective**: it tried to neutralize ECU's mobile assumptions in prose
  while leaving the mobile content in place.
- Part 2 rewrote it. Neutralisation now happens by deletion at build time, so the rule became a
  positive platform spec instead of an apology for content that is no longer there. See below.

## Decisions I made (assumptions)

- **Repo name** was originally `cloud-nine-unity` (user-chosen, "cloud nine" pun; an earlier
  "cloude-nine" typo was corrected to a single consistent spelling). It was later renamed to
  Kinglet Pioneer; the current repo is `kinglet-unity`.
- **Design docs path** `docs/` at project root (lowercase), created in the **user's Unity project**,
  not in this repo. Subfolders: `docs/design`, `docs/adr`, `docs/production`.
- **5 design templates** = the 3 named in scope (GDD, ADR, sprint-plan) + 2 the included commands
  directly produce (game-concept from `/brainstorm`, systems-index from `/map-systems`). Not
  gold-plating.
- **Health check** is a shell script (`scripts/studio-doctor.sh`) rather than a `/`-command, since it
  inspects the environment (Python/uv/MCP/files); avoids overlap with `/unity-doctor`.
- **Director agents** kept the APPROVE/CONCERNS/REJECT verdict format but lost the heavy gate registry.

---

# Part 2 — the standalone merge

ECU is no longer an upstream you install first. It is vendored into this repo at **v1.5.0
(`bb28ccb`)**, and Kinglet Pioneer (then named cloud-nine-unity) is a single toolkit with a single
installer. `.claude/VERSION` is **2.0.0** — ours, and a major bump because the install contract broke.

## What shipped

Counts verified against disk, not against anyone's README:

| | Count | Notes |
|---|---|---|
| Agents | **28** | 20 vendored `unity-*` + 8 adapted design roles |
| Commands | **36** | 27 vendored `unity-*` + 9 adapted design/production |
| Skills | **39** | 42 upstream − 3 mobile/mobile-genre |
| Rules | **6** | 5 vendored spine + `pc-console.md` |
| Hooks | **25** | `hooks/` holds 26 files, but `_lib.sh` is a sourced library, not a hook; `settings.json` registers exactly 25 |
| Design templates | **5** | `.claude/templates/` (repo-root `templates/` is 10 vendored C# code templates — a different thing) |

## Provenance replaces the directory split

Part 1 separated "ours" from "theirs" with a directory: payload lived in `overlay/`, and `install.sh`
mapped `overlay/<x>` → `<project>/.claude/<x>`. **`overlay/` is dissolved** — payload files now live
at `.claude/<x>` and install 1:1.

Directory-as-provenance doesn't survive vendoring: once ECU's files are in the tree, the layout can no
longer tell you who wrote what. So `provenance.tsv` does it explicitly — one row per tracked file
with `origin`, `upstream_version`, `upstream_path`, `upstream_sha256`, `status`, and a `note`.
`provenance-skip.tsv` records the inverse (what we deliberately did *not* vendor), distinguishing
`rule=absent` (must never exist) from `rule=ours-wins` (upstream has the path; we ship our own file
there).

`scripts/check-provenance.sh` validates both **bidirectionally** — no rows without files, no files
without rows, no `rule=absent` path back from the dead. One-way checking is what lets a manifest
quietly rot. `--online` re-fetches the pinned ECU commit and `cmp`s every `status=verbatim` row
against it; that is the only mode that verifies `verbatim` is true rather than merely asserted.

## Mobile: removed, not ignored

Part 1 said the mobile skill was untouched and "harmlessly inert on PC/console." **That was wrong on
both counts, and it was my error.** The skill shipped `alwaysApply: true` with `globs: ["**/*.cs"]`,
so it loaded on **every C# file** — it was the only non-core skill that always applied. Upstream's
own `docs/SKILL-CATALOG.md` said so plainly: "Always loaded (`**/*.cs`)". Nobody checked; the claim
was repeated across the README, `pc-console.md`, and this file.

- **Deleted:** `skills/platform/mobile` (and the now-empty `platform/` category),
  `genre/hyper-casual`, `genre/endless-runner`, and 2 mobile examples. 42 skills → 39; 6 examples →
  4. `hyper-casual` globbed `**/Level*.cs` and `**/GameManager*.cs`, so any PC game with a
  `GameManager` pulled in ad-monetization guidance.
- **Inverted the harmful bits.** Deleting files alone would have left `unity-shader-dev` saying
  "Never use compute shaders" and `unity-optimizer` saying "Don't use VFX Graph or compute shaders —
  they don't work on mobile." On PC/console both are wrong and actively harmful. Also reframed the
  mobile perf budget table, the touch input section, and the platform-defines hook's Android/iOS
  examples.
- **Prose sweep** across agents, commands, skills, docs and examples: virtual joystick →
  twin-stick/mouse-aim, ASTC → BC7/BC5, thermal/battery → GPU vendor variance + quality scaling,
  Android/iOS → PS5/Xbox/Standalone. Blind matching was a real hazard: case-insensitive `/ASTC/`
  matches the "astC" inside `castCount`, and `isTouchingWall` is physics, not touch. Every hit was
  read in context.
- **`tests/test-no-mobile.sh` makes it stick** (11/11). Without a test, the next upstream sync
  quietly reinstates all of it.

One Part 1 claim died here too: `pc-console.md` said `performance.md` was full of mobile framing
(TBDR, ASTC, thermal, safe-area). **It isn't.** `performance.md`'s only mobile mentions are an
atlas-size line that already distinguishes desktop and a platform-neutral "click/touch detection"
note. That content lived in the mobile *skill*; `pc-console.md` was misattributing it. So
`performance.md` needed no edit.

## MCP

- Part 1 **did not** ship a `settings.json` — ECU's already had
  `mcpServers.unityMCP → http://localhost:8080/mcp`, and `install.sh` only *verified* the entry and
  warned if absent. We ship `.claude/settings.json` now because there is no ECU install to inherit
  it from — but it does **not** carry an `mcpServers` entry, and never has: Claude Code silently
  ignores an `mcpServers` key in `settings.json` (see the source-projects table above). The
  `unityMCP → http://localhost:8080/mcp` entry lives in `.mcp.json` at the project root instead,
  written by `install.sh`'s own step, independent of `.claude/settings.json`.
- The vendored `unity-mcp-patterns` skill uses CoplayDev's `snake_case` tool names (`manage_scene`,
  `manage_gameobject`, `batch_execute`, `read_console`, …) → no tool-name rework needed.
- **The CoplayDev version reference was stale, not broken.** Docs said `9.7.x`; current is **10.1.0**
  (released 2026-07-13). Verified before bumping the reference: the UPM git URL
  (`?path=/MCPForUnity#main`) and the tool names our skill depends on are unchanged across the
  9.7 → 10.1 span, so nothing breaks. It's a documentation correction, not a migration.
- `install.sh --with-mcp` adds `com.coplaydev.unity-mcp` to `Packages/manifest.json` — a surgical
  insert with a `.bak`, restored on failure (see below for why it isn't a JSON round-trip any more).
- The design/production agents and commands still **do not call MCP** — they're a doc layer.

## Upstream defects found and fixed

Vendoring meant reading the code rather than depending on it, and the reading turned up bugs. These
are recorded here because someone will eventually diff a file against upstream, find it different,
and want to know why.

**The `CLAUDE.md` data-loss bug (reproduced, then fixed).** `generate-claude-md.sh` wrote
`$PROJECT_DIR/CLAUDE.md` itself *and* logged to stdout, while `install.sh` called it as
`generate-claude-md.sh "$dir" > "$CLAUDE_MD"`. Two writers, one file, independent offsets.
Reproduced against a mock project:

- *Fresh install:* the trailing status line landed mid-document and punched out the Unity Version and
  Render Pipeline rows — the file's whole reason to exist.
- *Existing `CLAUDE.md`:* `install.sh` redirects to `CLAUDE.md.generated` precisely to protect the
  user. The generator ignored that and overwrote the real `CLAUDE.md` anyway; `.generated` received
  only `[INFO]` chatter. **The guard destroyed the file it was meant to save.**

Upstream's own test only asserted that `CLAUDE.md` *exists*, which is why it shipped. Fix: the
document goes to stdout, every log to stderr, and the caller owns the destination — the generator
opens no output file at all, so it cannot do this even in principle. `install.sh` decides: no
`CLAUDE.md` → write it; markers present → refresh only the fenced region and leave your prose
byte-identical; markers absent → write `.generated` and touch nothing.

**The uninstall-by-name bug.** `uninstall.sh` removed files by filename with no provenance check,
while `install.sh` *skipped* on a name clash — so install would correctly leave your file alone and
uninstall would then delete it. It printed "ECU is untouched", which was asserted, not enforced.
Latent at 23 files; a 145-file payload makes it live. Fix: `install.sh` writes
`.claude/state/install-receipt.tsv` (path, sha256, mode, origin), and uninstall removes a file only
if its checksum still matches what we recorded writing. With no receipt it refuses rather than
guessing — a teammate's `git clone` carries `.claude/` but not the receipt, because the receipt
records what was written to *this* filesystem.

**Smaller ones, same sweep:**

- **Manifest arrays.** Hand-synced filename lists lived in three scripts. The payload is now
  enumerated at runtime with `find`, which cannot drift.
- `--help` printed `set -euo pipefail`, because `sed` ranges over your own source drift the moment
  the header changes.
- `--project-dir` with no value exited 1 silently: `shift 2` fails under `set -u` before the error
  message can print. Now validated first.
- Summary counts were typed into an `echo` (22 hooks / 22 commands / 41 skills while shipping
  25/27/42). Now computed — and hooks are counted from `settings.json`, since `hooks/` also holds
  `_lib.sh`, which is a library, not a hook.
- `--with-mcp` round-tripped the user's whole `Packages/manifest.json` through a re-indenting JSON
  dump to add one line. Now a surgical insert with a `.bak`.
- `.gitignore` was only updated if it already existed.
- **macOS portability:** `declare -A` needs bash 4 (macOS ships 3.2) and `grep -oP` is GNU-only.
  `.gitattributes` says we target macOS, so both are now portable.
- Skill suggestions named `unity-input-system` and `unity-general` — paths that match nothing. Now
  real catalog paths.
- `studio-doctor.sh` always exited 0, which made it useless in CI. It exits 1 on any FAIL.

## Licensing (no defer option)

Vendoring makes us the redistributor of 145 MIT files into every user's project. `.claude/NOTICE.md`
ships into the project with the upstream notices reproduced verbatim — upstream copies 125 MIT files
into user projects and ships no notice at all; we must not inherit that.

ECU's `LICENSE` reads "Copyright (c) 2026" with **no holder named**. It is reproduced verbatim and
annotated, **not** "corrected" to a name: writing a holder into someone else's copyright notice is
not ours to do.

`.claude/VERSION` is ours (2.0.0). The vendored pins live in `.claude/UPSTREAM` and `provenance.tsv`.
**LICENSE holder** is `OmerZeyveli` (Part 1 shipped a neutral `cloud-nine-unity contributors`
placeholder).

## Known risk: staleness, not fragility

**The old risk is gone.** Part 1 warned that `install.sh` detected ECU by the presence of
`.claude/rules/architecture.md` and `.claude/skills/core/unity-mcp-patterns/SKILL.md` and placed
files *alongside* ECU's — so an ECU release that renamed or moved those files would break both
detection and placement. There is no detection gate any more, and nothing to place alongside. That
marker-file coupling died with it.

**The new risk is the trade we made.** Vendoring swaps *drift risk* for *staleness risk*. We no
longer break when ECU moves a file — but we no longer receive ECU's fixes either, and the failure is
silent. Nothing tells us upstream has patched a hook we shipped a copy of; the toolkit just keeps
working, slightly wrong, indefinitely.

Mitigation is deliberate, not automatic:

- `provenance.tsv` records the exact upstream path and `sha256` of every vendored file, so a future
  ECU bump is a **diff**, not a re-merge.
- `check-provenance.sh --online` re-fetches the pinned commit and reports which `verbatim` files have
  drifted — the honest answer to "is this still what upstream says?"
- `provenance-skip.tsv` makes a re-vendor report "still skipped" instead of silently reinstating the
  mobile content we removed on purpose.

Re-verify against newer ECU releases before bumping the pin in `.claude/UPSTREAM`. Sync is a
decision, and it should stay one.

---

# Part 3 — the 2026-08-03 surface cut

The pool went from 103 surfaces (agents + commands + skills + hooks) to 32, on one criterion: **a
surface survives only if it does something the model cannot do unaided.** Selection is a scarce
resource — every extra agent, command, or skill is one more thing competing for the same trigger
phrase, and a well-tuned competitor plugin (Superpowers) wins the ones that are ambiguous. `provenance-skip.tsv`
records the removal, one row per path, `rule=absent`; `scripts/check-provenance.sh` fails if any of
those paths ever exist again. What follows groups the ~77 dated `2026-08-03` rows by why they left,
with the evidence for each group.

## Cut: the Donchitos design/production layer (23 rows)

**Taken** in Part 1 (8 agents, 9 commands, 5 templates — see "Taken from Donchitos and adapted"
above), still shipping as of the last MERGE-NOTES update. **Cut** entirely. Evidence: a field note
(field note 36) measured `docs/design`, `docs/production`, and `docs/adr` output on a real project and
found all three used 0 of 3 in the session that generated them — the layer produced documents nobody
read. `.claude/agents/game-designer.md` and its seven siblings, the nine `/brainstorm`-family
commands, and the associated templates are now `rule=absent`. The reasoning that justified adapting
them in the first place is kept in Part 1 above, unedited, because a build record that quietly deletes
its own history isn't one — Part 2's rule still applies: where the two disagree, the newer decision
wins, and this is that disagreement.

## Cut: ECU specialist agents and their commands (9 + associated commands)

Agents whose one job could be folded into a broader surface without losing anything a real session
used: read-only reviewers/scouts that duplicated `unity-reviewer`'s read-only pass, a security
reviewer with no measured invocation, a migration agent for a one-time task, a git-operations agent
that duplicated what `Bash` already does unassisted, a shader specialist and a networking specialist
whose domains are thin slices of what `unity-coder` already covers, and their orphaned commands.
`provenance-skip.tsv` note: *"specialist removed 2026-08-03; surface cut to 32 on the criterion that a
surface survives only if it does something the model cannot do unaided."*

## Cut: "lite" speed variants (3 rows)

`unity-coder-lite` and `unity-fixer-lite` (and one associated command) existed only to trade quality
for speed on a cost axis. Note: *"speed variant removed 2026-08-03; twins an existing surface on a
cost axis, doubling the selection pool with nothing to discriminate on."* Removing them halves the
ambiguity between "coder" and "coder-lite" without losing a capability — the full agent is still
available when speed doesn't matter, and nothing distinguished when it does.

## Cut: mobile and genre-template skills (9 rows)

Genre skills (`idle-clicker`, `match3`, `puzzle`, `rpg`, `topdown`, `endless-runner`,
`hyper-casual`, and siblings) removed on the same scarcity argument, plus the two mobile-specific
genres removed earlier for loading on globs any PC game trips. Note: *"genre template removed
2026-08-03; the model knows these genres and selection pool size is the scarce resource"* — Sonnet and
Opus already know what a match-3 or idle-clicker architecture looks like; the skill's marginal value
was one more competing description, not new knowledge.

## Cut: a skill that duplicated an auto-loading rule (3 rows)

`serialization-safety` and its relatives are gone because `.claude/rules/serialization.md` already
answers the question unconditionally — rules load on every session, skills only load if selected.
Evidence: the regression probe in Task 7 Step 6 (see `docs/research/pioneer/smoke-pass.md`, dated
section below) asked the exact serialization-rename question and got the correct answer from the rule
with **zero tool calls** — the skill was never invoked because the rule had already answered before
selection could happen. A surface being selected for a question a rule already answers would be a
regression, not a win; keeping the skill risked exactly that.

## Cut: orphaned surfaces (23 rows)

Commands and skills whose only reason to exist was another surface that is now gone — `producer`
skills with no surviving agent to feed, package-conditional skills for packages no example project
uses, toolkit self-references (a command that existed to document this repo to itself), and one
upgrade-flow skill superseded by the receipt-driven re-install from Part 2. Notes: *"orphaned
2026-08-03; producer removed in the design/production track cut and no surviving agent/command
produces it"* and *"removed 2026-08-03; orphaned, package-conditional, or toolkit self-reference."*

## What survived and what was added

32 surfaces: 8 agents, 11 commands, 13 skills, 27 registered hooks (28 files including `_lib.sh`), 6
rules. Every surviving surface got a trigger-condition description (Task 4) so selection has something
concrete to match against instead of a one-line summary. Three original skills were added in the same
wave to carry a process chain rather than remove one: `using-kinglet` (session-start orientation
across the whole surface set), `systematic-debugging` (investigate before proposing a fix), and
`verification-before-completion` (evidence before claiming done) — see `provenance.tsv`, `origin:
original`. A proactive-suggestion layer was added to the command bodies so a command offers the
logical next step rather than requiring the user to already know the chain.

**A fourteenth skill, added afterward.** `subagent-driven-implementation` (adapted from Superpowers'
`subagent-driven-development`) shipped in the `process-layer-2` wave that built the execution loop
(`implementer-prompt.md`, `task-reviewer-prompt.md`, `re-review-prompt.md`) it documents. It is
`/unity-workflow`'s alternative to inline execution. Current count: 33 surfaces — 8 agents, 11
commands, 14 skills — the same 27 registered hooks and 6 rules unchanged. `docs/SKILL-CATALOG.md`,
`README.md`, and `docs/ARCHITECTURE.md` carry the updated skill count; this section is left at its
original 13/32 above because it is a record of what Task 4's cut produced, not a running total.

## The gap this plan corrected

The original spec for this wave assumed `tests/test-skill-discovery.sh` would catch dangling
references left by the cut. Measured: it matches **path-form** references only
(`.claude/skills/<name>/SKILL.md`), and no surviving surface had one pointing at a removed skill — the
check returned clean while nine **bare-name** references (a skill named without its path) still
pointed at nothing. `tests/test-surface-references.sh` was added to close that gap; it is a smaller
cleanup than the spec anticipated, but a worse blind spot, because a bare-name reference produces no
error anywhere in the existing suite.

## The measurement this whole wave is a hypothesis until

Every claim above — that removing 74-odd surfaces raises the odds a Kinglet surface gets selected over
a well-tuned competitor plugin, and that the process-chain skills don't create the regression they're
meant to prevent — is unverified until it runs against a real `claude` session with the competitor
enabled. That measurement is recorded in `docs/research/pioneer/smoke-pass.md`, in the dated section
this task appended; see that file for the actual tool-call outcomes, not an assumption made here.

## Two history items, left as-is rather than rewriting 37 commits

Both surfaced in the final whole-branch review of this wave. Fixing either means rewriting published
history; both are benign in direction, so neither was fixed.

- **A bisect-red range: `2b543f2..f6d517b`.** `2b543f2` (`chore(baseline): record the surface cut`)
  regenerated `migration/baseline-inventory.json` but left `tests/kinglet/test_baseline_inventory.py`'s
  hardcoded `EXPECTED_COUNTS` and `full_claude_tree` constants asserting the pre-cut numbers, so the
  suite fails at that commit and still fails at `f6d517b` (which fixed only `EXPECTED_COUNTS`, not the
  second constant). Green resumes at `ab49fc3`. A `git bisect` that walks through this range will land
  on a red commit that is not the cause of whatever it's looking for — know this range going in.
- **Provenance rows flipped one commit early.** `509bb9a` marked
  `unity-feature.md`/`unity-fix.md`/`unity-init.md`/`unity-prototype.md` as `status=modified` in
  `provenance.tsv`; the edits those rows describe didn't land until the next commit, `bbad983`. The
  manifest under-claims fidelity for one commit rather than over-claiming it, which is the safe
  direction for this kind of drift.

## unity-brainstorming (was deep-interview): the full note history

`provenance.tsv`'s `note` column is free text that `scripts/check-provenance.sh` never reads. This
row's note had accumulated five unrelated historical clauses, and the 2026-08-03 ledger deferred the
readability question with an explicit trigger — *"may need a rethink if another wave adds a fifth."*
The 2026-08-10 process-chain wave was the trigger. The note now carries one summary clause plus a
pointer here; the prose history it used to carry is below, unchanged in substance.

The file is `origin=ecu` and stays so. ECU 1.5.0's Ambiguity Score survives the 2026-08-10 rewrite:
the 0–2 scale, the five dimensions, the `>= 6` threshold, the interview protocol's first three steps
and both scoring examples — **32 of ECU's 69 substantive lines**, verbatim.

One ECU line was deliberately not kept. Its interview protocol's fourth step ended by allowing the
user to opt out explicitly, which was the deleted `--skip-interview` exemption in other clothes and
contradicted the Handoff in the same file: an opt-out permitted at one heading and forbidden at
another. The step's stem survives and now proceeds *to* presenting the design rather than past it.
That is the whole of the difference between 33 and 32.

Both halves are checked rather than asserted. Each named block is compared **whole** in
`tests/test-surface-references.sh` — the 0–2 table, the dimensions, protocol steps 1–3 and both
scoring examples — because a per-line needle lets a whole section vanish green (measured: 153 of 176
lines could be deleted one at a time with the suite green, and dropping just `## Interview Protocol`
and `## Scoring Examples` took the survivor count from 33 to 14). The **number** is re-derived in
`tests/test-derived-counts.sh` and compared against the figure quoted here and in `provenance.tsv`,
so it cannot go stale the way the five-row claim in clause 5 below did. The derivation is a line-by-
line comparison against `git show 45eada9:.claude/skills/core/deep-interview/SKILL.md`.

The Superpowers adaptation is recorded in the note and discharged in `CREDITS.md` and
`.claude/NOTICE.md`, which is where licence obligations belong; the schema has one origin column and
the lineage begins at ECU.

Clause by clause, oldest first:

1. **`mobile-strip`** — the initial vendoring removed ECU's mobile-targeted guidance from this file
   along with every other, per `tests/test-no-mobile.sh`. The one surviving trace was the question-style
   example, which asked "Is this for mobile (touch input, limited GPU) or desktop?"; it was rewritten
   to a keyboard/gamepad and min-spec-60fps question.
2. **`flattened-for-discovery+inert-frontmatter-stripped`** — moved from
   `.claude/skills/core/deep-interview/SKILL.md` to the flat path Claude Code actually scans, and
   `alwaysApply: true` was deleted from the frontmatter as an inert Cursor key.
3. **`task-5-process-chain`** — appended a Handoff section routing a passed gate to `/unity-workflow`
   or `/unity-feature` and a failed gate to stop and ask. Both of those commands are deleted in the
   2026-08-10 wave and the handoff now names `unity-planning` and forbids the alternatives.
4. **`task-5-r1-finding-1`** — the description was rewritten into the trigger-condition form from
   `docs/superpowers/plans/2026-07-30-kinglet-pioneer-wave-1b2-make-it-findable.md:70`. It is the
   chain's entry point and it stated what it did rather than when it applied, so it could not be
   selected from a vague request. That form was superseded on 2026-08-10 by the category trigger:
   the surface no longer decides whether the request is vague enough to warrant it.
5. **`task-2-process-layer-2`** — added "the thought that means you are about to treat vague as
   clear", sourced from that wave's own record (repeatedly re-asked questions; briefs followed
   exactly still producing findings clustered where the brief was vague). The note still says "five
   rows" and the file has carried two since `e994779` ("cut unsourced citations"), which dropped
   *"I can infer which file/system this means"*, *"Asking is slower than doing"* and *"The brief
   didn't say, so it must not matter"* for citing sources that could not be produced. The two that
   survive are measured and the 2026-08-10 rewrite keeps both. That drift — a note asserting a count
   the file stopped matching two commits later — is a second argument for collapsing this column: a
   number in free text is a number nothing checks.
6. **`2026-08-10 process chain`** — the rename and the rewrite the current note summarises.

The claims this file makes about its own content are asserted in `tests/test-surface-references.sh`,
which is what stops the summary above becoming another sentence nobody can falsify.
