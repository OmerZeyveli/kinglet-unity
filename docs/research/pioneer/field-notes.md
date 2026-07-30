# Field notes — what running Kinglet Pioneer on a real project taught

Findings from installing Pioneer into **Endless Evolution** (Unity 6000.0.68f1, URP, ~150
first-party C# files) and running four parallel agent tracks against it on 2026-07-30.

These are lessons for the toolkit, kept separate from `smoke-pass.md`, which records the
installation measurement itself. Everything here was observed, not inferred.

---

## 1. A Unity `.csproj` is a file list, and a compile gate built on one is blind to new files

**The defect.** The parallel-work recipe gave every agent a compile gate:

```bash
cp "$MAIN"/*.csproj "$WORKTREE"/
ln -sfn "$MAIN/Library" "$WORKTREE/Library"
dotnet build Assembly-CSharp.csproj -p:BaseIntermediateOutputPath=… -p:BaseOutputPath=…
```

It runs in 2–12 seconds, needs no Unity, and writes nothing into the repository. All true, and it
still had a hole big enough to hide the entire deliverable.

**Unity generates `.csproj` files that enumerate their source files explicitly.** The copied
`.csproj` was generated at a fixed moment. Every file created after that moment — 16 new test specs
carrying 190 tests, and two extracted classes — was **absent from the build**. The gate reported
`0 Error(s)` throughout and had never compiled a line of the work it was supposedly gating.

It only surfaced at integration, as a phantom error: `Enemy.cs` referencing `ThrowBallisticsSettings`,
a type that *is* defined, `public`, in a file that *does* exist — but in a file the `.csproj` did
not list.

**What makes this worth recording** is that every symptom pointed away from the cause. Agents saw
green. The error, when it came, named a type-not-found in code that was correct. Nothing in the
failure mode said "your build is not seeing new files".

**The rule.** A compile gate over a generated, file-enumerating project must either regenerate that
project or verify the file set. Concretely, before trusting it:

```bash
# every tracked first-party .cs must appear in some csproj
comm -23 <(git ls-files '*.cs' | grep -v Extensions/ | sort) \
         <(grep -ho '[^"\\]*\.cs' ./*.csproj | sort -u)
```

Empty output, or the gate is lying. **Cheap, and it would have caught this on the first run.**

**For Pioneer:** any future guidance that hands agents a `dotnet build` gate for a Unity project
must ship this check beside it. The gate is genuinely good — fast, isolated, no Editor needed — and
it is unsafe without the file-set assertion.

---

## 2. Regenerating the project files needs Unity, which the recipe assumed away

Following from the above: the fix is not a shell workaround. `.csproj` regeneration is done by the
Editor. So a workflow that keeps Unity closed for isolation **must schedule an Editor pass whenever
files are added**, not only at the end for human verification.

The plan already required a final Editor session for behavioural verification. What it missed is
that adding a file is itself an event requiring Unity. **Adding files and keeping Unity closed are
in tension**, and the plan should say so rather than discovering it at integration.

---

## 3. "Read-only until the net exists" worked, and the phrasing mattered

Four tracks ran with an explicit rule: report, do not change, until the test track lands.
Findings were classified **Certain / Behavioural / Structural** with a stated bar:

> not *am I confident this is better* — but **would a wrong answer here stay invisible until someone
> plays the game**.

The correctness track found **137 Certain, 143 Behavioural, 37 Structural** and applied none in
phase 1. More usefully, it *withheld* two findings from the Certain list — a hazard's kill trigger
and an audio pitch randomisation — on the ground that both were plainly wrong but the right **value**
was a design call. That is the discipline working: the bar produced a judgement the agent would not
have reached from "fix what is broken".

**For Pioneer:** this three-way classification, with that specific bar, is worth building into the
review surfaces rather than leaving to a plan author to reinvent. The wording carries the weight —
"am I confident" invites confidence; "would it stay invisible" invites imagination about failure.

---

## 4. "No test, no fix" is right for behaviour and wrong for everything else

The same rule, applied bluntly, would have frozen ~130 of the 137 Certain findings — because most
sat in code the net did not cover, and many were not behavioural at all: dead code, unused fields, a
comment contradicting its function, an unreachable branch.

**A test is the wrong instrument for those.** The compiler and a small readable diff verify them.
Splitting the rule was necessary:

- **behaviour-changing** → a test that fails before and passes after;
- **non-behavioural** → the compile gate and a diff small enough to read.

**For Pioneer:** worth stating in the discipline layer directly. "No test, no fix" is a good slogan
and a bad rule; the useful form names what each class of change is actually verified by.

---

## 5. A guard's scope is the first thing to check, and the last thing anyone checks

This recurred so often during Wave 1b-1 that it deserves its own note, and it recurred again here.

Every instance had the same shape: a guard whose **name and comment imply a class**, whose
**implementation covers one directory of it**.

- `test-bash32-compat.sh` — named for shipped scripts, scanned `.claude/hooks/*.sh` only, while five
  scripts under `scripts/` used `declare -A`, a hard parse failure on macOS.
- The early-exit-pipe sweep — scoped to `scripts/` and `tests/`, leaving `.claude/hooks/`, where the
  same shape made three **blocking** hooks silently allow what they exist to block on files over
  ~36 KB.
- The MCP-doc guard — a `.{0,120}` proximity window that missed a live false claim by six characters.
- `test-no-mobile.sh` — filters its allowlist against whole `grep -rn` lines, so any line whose
  *content* mentions an allowlisted filename is dropped regardless of path.

**The check is cheap:** read the guard's name, read what it globs, and ask whether the second covers
the first. **For Pioneer:** every guard should state its scope in its own header, and any guard whose
scope is narrower than its name should say why in the same breath.

---

## 6. The competing-plugin measurement, and what it actually proved

`smoke-pass.md` §4 recorded that no Kinglet surface was ever selected for an ordinary request, and
concluded the descriptions were not selectable. **That conclusion was too strong** — a point the
operator raised, and the measurement settled (§10).

With the competing plugin disabled at **project scope**, three ordinary prompts selected
`/unity-feature`, `unity-fixer` and `unity-optimize` on the first try. Pioneer's descriptions win
when uncontested; they lose head to head against trigger-phrased ones.

**Two things follow.** Pioneer is installable and useful today, with a one-line project-scoped
setting — a fact worth documenting for users rather than leaving as tribal knowledge. And Wave 1b-2
remains worth building, because winning by removing the competitor is weaker than winning on merit.

**The general lesson is about the inference, not the plugin.** "X never happened" supports "X was
never selected"; it does not support "X could never be selected". The distinction cost a wave's
worth of sequencing until someone asked the obvious question.

---

## 7. Handover held up

Pioneer was designed so the full Kinglet platform could take a project over cleanly: brand-level
markers (`kinglet:generated:begin`), a receipt headed `# kinglet install receipt` with
`# edition: pioneer` beside it as data.

Installed into a project that **already had its own `CLAUDE.md`**, the installer wrote
`CLAUDE.md.generated` beside it and left the original untouched — verified by `git diff`. When the
owner later authorised editing it, the consolidation merged the generated block into the real
`CLAUDE.md` **with its markers intact**, so a future `install.sh` upgrade still finds its own block
and refreshes only that.

**That is the design working as intended**, and it is the first time it has been exercised against a
project with a pre-existing guidance system. Worth keeping as the reference case.

---

## 8. The csproj blindness came back wearing asmdefs

§1 said a compile gate over a generated, file-enumerating project must regenerate it or verify its
file set. That rule was written, shipped as guidance, and the defect still recurred within a day —
in a form the rule as phrased did not cover.

Introducing asmdefs makes Unity emit **new** project files (`EndlessEvolution.Runtime.csproj` and
friends). It does **not** delete the ones they replace. So `Assembly-CSharp.csproj` stayed on disk,
three hours stale, orphaned — no longer regenerated by anything, and still the exact file the gate
recipe named. The file set inside it was *correct at the moment it was abandoned*, so the §1 check
(`comm -23`) would have passed. It would have gone on passing while drifting further from reality
with every added file.

Two things made it invisible. `*.csproj` is gitignored, so it never appears in `git status`. And the
gate reports what it was pointed at, not whether the thing it was pointed at is still maintained.

**The rule §1 should have said:** verify the project file is *current*, not just that its contents
agree with the tree. A file-set check answers "does this list match?"; it does not answer "is anyone
still writing this list?" An mtime compared against the last Editor run answers the second, and is
just as cheap.

**For Pioneer:** any guidance that hands agents a `dotnet build` gate must name the assembly-specific
csproj, not `Assembly-CSharp.csproj`, whenever the project has asmdefs — and should delete the
superseded files rather than leave them to be found.

---

## 9. A drift test earns its keep at integration, and its blind spot bites there too

A documentation-map test — mechanically checkable claims only: cited paths exist, cited line numbers
are in range, every runtime script is named by some subsystem document, every documented
`Type.Member` still appears in its declaring file — was written by one track and validated at the
merge of four.

It caught, on that first integration, that **three separate tracks had each added a new file and
updated no document**: two extracted interfaces and their implementation. None of the three agents
noticed. No human reading four reports would have noticed either. This is the strongest argument for
the test's existence: it catches what the agents forgot, which is a different set from what they got
wrong.

The same test's disclosed blind spot bit in the same session. A track "fixed" a doc citation from
`DeathState.OnEnter` to `DeathState.Enter`; the method that actually does the work is `Exit`. The
test passed, because it checks that the member *name appears in the declaring file*, and `Enter`
does appear — it is simply the wrong method. **A name-presence check catches deletion and renaming;
it cannot catch a citation that is wrong but plausible.** Two tracks disagreed in their docs (`Exit`
vs `Enter`) and only reading the source settled it.

**For Pioneer:** worth shipping this test shape, and worth shipping the caveat with it, because the
caveat is what tells a reader when to still go look. Also worth noting the tension it creates:
prose that records history ("was `SaveManager.TryLoadFromPath` before the extraction") reads to the
test as a live claim about a member that no longer exists. Historical notes need phrasing that does
not look like a citation, or the test needs an escape marker — this one has `<!-- map-check:
allow-missing -->`, which is the right shape.

---

## 10. Parallel agents pay for breadth and lose money on bottlenecks

Two rounds of four agents on the same project, same operator, same prompt discipline, ten-fold
difference in output. The variable was not the agents.

**Round 1 — four independent read-only sweeps, one per source directory.** Thirty-plus commits.
Every track moved the whole time because no track needed anything from another.

**Round 2 — three tracks whose work depended on one track's deliverable.** Five commits total. One
track produced *nothing* (its work was gated on an unlock that never came). One track, forbidden
from writing documentation, wrote documentation — the only unblocked thing left to it. The
bottleneck track hit a genuine external blocker and stopped.

**The rule: parallelise breadth, serialise bottlenecks.** Handing a bottleneck to four agents does
not make it four times faster; it idles three of them and produces make-work. When a deliverable is
a prerequisite for everyone, one worker owns it and the others get work that does not touch it — or
the operator clears it directly, which is what finally happened here.

**The corollary is a planning duty, not an execution one.** Before fanning out, ask of each track:
*if track N returns nothing, does track M still have a full session of work?* If the answer is no
for more than one track, the fan-out is wrong regardless of how good the individual prompts are.

**For Pioneer:** any surface that plans parallel work should force this question explicitly. It is
cheap to ask and it was the difference between the two rounds.

---

## 11. Integrate continuously, or pay for it all at once

Every expensive surprise in this exercise surfaced at integration, and none of them had to.

- Three tracks each added a new source file and none updated the subsystem docs. No individual track
  was wrong; the gap only existed in aggregate. A human reading four reports would not have caught it.
- Two tracks independently performed the *same* task — repointing the compile gate in the docs after
  the assembly change — because neither knew the other was doing it. The duplicated work then
  presented as a merge conflict, which is the expensive way to learn it.
- A stale, orphaned project file that made the gate meaningless sat undetected through both rounds
  because it is gitignored, so it never appeared in anyone's `git status`.

All three are integration-interval defects. They are invisible inside a single track by
construction, and their cost scales with how long the tracks stay apart.

**The fix is not more review. It is a shorter interval:** each track merges to the integration branch
as soon as one unit of work is green, rather than diverging for a session and merging at the end. A
duplicate task is then caught the moment the second agent pulls; a doc gap fires the drift test on
the next merge rather than the last one.

**For Pioneer:** worth stating in the parallel-work guidance as a rule with a reason, because the
default instinct — "finish your track, then integrate" — is exactly backwards for agent work, where
the tracks cannot see each other at all.

---

## 12. Taking over an existing project: what actually cost time

Installing into a real, unfamiliar Unity project (~150 first-party files, four contributors, a
pre-existing `AGENTS.md` documentation layer). What was expected to be hard mostly was not; the time
went elsewhere.

**Cheap, despite the reputation:**

- **Assembly definitions.** The measured minimum was three assemblies (runtime, editor, tests), not a
  per-folder split. The three things that genuinely break when a type changes assembly —
  `[SerializeReference]`, `Type.GetType`, `Assembly.Load` — occurred zero times. Scene and prefab
  wiring is `.meta` GUID + `fileID`, so it is assembly-independent and did not care. A missed package
  reference is a loud compile error, not a silent break.
- **The implementation shape is worth copying:** one `.asmdef` in a new empty folder, plus an
  `.asmref` in each existing source folder pointing at it. No file moves, so no `.meta`/GUID churn,
  and it sidesteps the fact that an asmdef cannot be rooted at `Assets/` without swallowing the
  vendored tree.
- **The trap inside it:** a folder named `Editor` loses its automatic editor-only status once it is
  inside an asmdef tree. Every stray editor folder outside the main one needs its own editor
  `.asmref`, and forgetting one puts editor code in a player build.

**Expensive, and mostly unforeseen:**

- **Search noise.** 923 vendored `.cs` files against 169 first-party ones. Every search an agent ran
  was ~85% code nobody would ever change. Fixed with a root `.ignore` file (ripgrep/fd convention —
  *not* `.gitignore`, because the vendored tree is legitimately tracked): a search for `Instance`
  went from 124 files, 56 of them vendor, to 68 with zero vendor. Document the `--no-ignore` escape
  hatch in the same breath or someone will conclude the tool is broken.
- **Opening the project rewrote `ProjectSettings`.** `TimeManager.asset`'s `Fixed Timestep` upgraded
  to `serializedVersion: 2` (same 50 Hz, new rational-number format) on every editor open, showing as
  a permanent uncommitted change. It was initially misread as a wrong-editor-version footprint; it is
  not — it reproduces with the pinned version. Worth knowing before it gets committed as an accidental
  engine upgrade, and worth having automation revert it rather than argue about it.
- **Pinning the editor version is load-bearing.** Any automation that launches Unity must resolve the
  binary from `ProjectSettings/ProjectVersion.txt`, never from `PATH` or "whatever is newest in the
  Hub". A newer editor opening the project rewrites serialized settings, and in a batch script that
  becomes a silent committed upgrade.
- **The existing documentation layer was the most valuable thing in the repo and the least
  trustworthy.** Several `AGENTS.md` files, written by different people at different times, with real
  knowledge in them and no mechanism keeping any of it true. Retiring them wholesale would have thrown
  away genuine institutional knowledge — the useful move was to consolidate, then make the result
  self-verifying (see §9).

---

## 13. What agents did that the prompts had to be changed for

Behaviours seen repeatedly across eight agent-sessions, each of which needed an explicit rule:

- **Silently dropping assigned items.** One agent delivered two of four items and its 947-line report
  never mentioned the other two — not as blocked, not as deferred. The individual work was rigorous;
  the omission was invisible precisely *because* the report was thorough. The rule that fixed it:
  *if you do not do something you were asked to do, write that down with the reason. Not finishing is
  normal. Not saying so is not.*
- **"Correcting" a name without reading the source.** An agent changed a documented method citation
  from `OnEnter` to `Enter`. The method that does the work is `Exit`. It passed every automated
  check, because `Enter` does exist in that file. Two agents' documents disagreed and only the source
  settled it. The rule: *read the source before you fix a name.*
- **Reports going stale against their own branch.** One report described a state six commits and one
  deliverable behind the branch tip. Anyone reading only that file would have materially misjudged
  what shipped. Worth requiring that the report is updated in the same commit as the last change, not
  as a separate final step that may never happen.
- **Work flowing to whatever is unblocked.** An agent told to produce architectural seams and
  forbidden from writing documentation produced one seam and eight documentation commits in round 1,
  and one documentation commit in round 2. This reads as disobedience and is better understood as
  water finding a level: the seams were hard, the docs were not, and nothing forced the agent to
  report that trade. Ask for the blocker explicitly and it gets reported.
- **Good behaviour worth naming, because it was not automatic:** the agents that performed best
  challenged the brief. One was handed a diagnosis of a state-machine coupling problem and measured
  it instead of implementing it — 82 reads, zero writes, no back-references — establishing the
  coupling was one-way, not mutual as stated, and corrected a proposed interface name that would have
  been "a lie at precisely the point a bug would hide." Prompts should invite this in so many words;
  the ones that did got it.

---

## 14. Gate design notes worth carrying

- **Order gates cheapest-first.** Source-layout check (~1s, no Unity, no generated files) → compile
  gate (~5s) → EditMode suite (~2m) → PlayMode suite (~1m). A broken change fails in seconds instead
  of minutes, which is what determines whether people leave the gate switched on.
- **Have a gate that needs no generated artifacts.** The csproj-based file-set assertion cannot run in
  CI at all, because `.csproj` is gitignored and does not exist there. The equivalent check against
  the source of truth — every `.cs` under `Assets/` is inside some `.asmdef`/`.asmref` tree, walking
  up — needs neither Unity nor project files and catches the same class of invisibility.
- **`core.hooksPath` beats `.git/hooks`.** Point it at a tracked directory and the hook is
  version-controlled, reviewable, and installs in any clone with one command. `.git/hooks` is
  per-clone, unversioned, and silently absent for everyone who did not set it up.
- **Every escape hatch should print what it gave up.** `SKIP_UNITY_TESTS=1` prints "compilation is
  proven; behaviour is not." A silent skip is indistinguishable from a pass three weeks later.
- **A local hook is not CI and should say so in its own header.** It is what runs while CI waits on a
  credential; it is local-only and `--no-verify` skips it. Stating that in the file prevents it from
  being mistaken for the real gate.
- **PlayMode is not free, and the first test should be about the harness.** A PlayMode assembly with
  no source files is never compiled by Unity, so "the asmdef exists" is not evidence the pipeline
  works. Four tests asserting only that `Awake`/`OnEnable` fire, that `Start` runs on the first frame
  boundary, that `OnDestroy` fires, and that `Time.time` advances — mutation-checked — turn an
  assumption into a fact and unblock everything downstream.

---

## 15. Smaller things worth carrying

- **`.gitignore`'s `/[Ll]ibrary/` is directory-only.** A symlink named `Library` does not match it,
  so every worktree shows it untracked. Fixed centrally via `.git/info/exclude`, which is shared
  across worktrees and never committed — better than editing a tracked file the owner did not ask to
  change.
- **An agent deleted four `.md` files and left their `.meta` files behind.** Unity's own guidance in
  that project warns about exactly this. Any surface that moves or deletes assets should pair the
  file and its `.meta` explicitly rather than trusting the agent to remember.
- **`Assembly-CSharp-Editor.csproj` can be stale-broken** in a way that self-heals on the next Editor
  open. Every worktree inherits it from the copy. Agents need to be told, or they investigate it as a
  regression they caused.
- **`git worktree add` with an invalid branch name fails, and a following `cd` fails with it** — and
  the rest of the script then runs in the original checkout. A trial merge intended for a scratch
  worktree landed on the real integration branch. **Any script that changes directory before doing
  something destructive should verify the directory changed.**
