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

---

## 16. Four agents, one working tree: the isolation that was never there

A second wave was set up with a per-track branch each and a line of prompt telling every terminal to
`git checkout -B hardening/track-N`. All four spent the wave editing the same working tree, and nobody
— including the session coordinating them — noticed for two hours.

- **A branch checked out in a worktree cannot be checked out anywhere else.** `git checkout -B` fails
  with a one-line error. An agent reads that error, decides it is not what it was asked about, and
  keeps working. The next commit it makes lands wherever HEAD already was. One commit here carried
  three tracks' work — a singleton seam, an unrelated editor-tool repair, and a new spec — on a branch
  a *fourth* terminal was live in.
- **Setup instructions must verify arrival, not assume it.** The fix is one line the agent cannot
  misread: `git rev-parse --show-toplevel` must equal the intended path, and the run stops if it does
  not. This is the same failure as §15's last bullet, so treat them as one rule: **after any command
  that is supposed to move you, assert that you moved.**
- **Stale worktrees make `git status` lie in the scariest available direction.** Each abandoned
  worktree's index had been built when HEAD was older, so status there showed the whole safety
  infrastructure — CI workflow, hooks, gate scripts — as *staged deletions*. Nothing was deleted; those
  files had never been written into those trees. But an agent running `git add -A` in one would have
  committed the removal of every gate built that day.

---

## 17. A rescue that snapshots "the working tree" loses the worktrees

The coordinating session had the right reflex when it found the tangle: snapshot every uncommitted
change and every untracked file before touching anything. It snapshotted the main checkout. Six
worktrees existed, and the recovery plan's next step was to delete them.

Two held work that existed nowhere else — twelve files including the PlayMode locomotion specs, their
rig harnesses, and the mutation verifier that proves a PlayMode test can fail at all; plus the tool
that finally answered a two-round-old open question. **`git worktree list` belongs at the top of any
recovery, before the first snapshot and long before the first deletion.**

Two discriminators made the sorting tractable, and both are worth knowing before you need them:

- **Untracked files cannot be phantom.** A file git has never seen is real work by construction. Index
  state can lie about deletions; `ls-files --others` cannot.
- **"Content not in the integration branch" does not mean "new".** These worktrees were two rounds old,
  so most of their differing files were *older* versions of files the branch had since moved past. The
  test that separates them: hash the file and look for that blob anywhere in history — walk
  `git rev-list --all -- <path>` comparing `<commit>:<path>`. A hit means stale. No hit while the path
  exists in the branch means someone edited it on top of current state. No hit and no path means
  genuinely new.

---

## 18. Ownership can be recovered from the code even when authorship cannot

Four cleared terminals were asked which files were theirs; the session died before any answered. The
attribution still came out, from the code:

- **A test belongs to whatever it compiles against.** One PlayMode spec looked like it belonged to the
  track that owns PlayMode testing. It exercised a field the *Environment* track had just deleted and a
  guard that track had just added, so it could only build on that track's branch. Coupling settled what
  a mandate could not.
- **A document change belongs to the change that made it true.** A dependency map claiming "no
  first-party code imports Cinemachine any more" belongs with the commit that removed the import, and
  `git show <commit> -- <file>` confirms which one in seconds.
- **When it stays ambiguous, quarantine beats guessing.** Four recovered specs went onto a branch named
  for what it is, with a commit message saying nothing merges it and the owner picks. They are in git —
  so a reboot cannot take them — and nobody had to invent an author.

---

## 19. Splitting a mixed commit is cheap; the document both halves touched is the only hard part

Redistributing a commit that carried three tracks' work took two `git checkout <commit> -- <paths>`
and one three-way merge. The merge is the part worth knowing: when both halves edited the same document
from the same base, `git merge-file` resolves it and **keeps both edits**, where a `git checkout` of
either side silently discards the other.

```bash
git show $BASE:doc.md > base.md; git show HEAD:doc.md > ours.md; git show $MIXED:doc.md > theirs.md
cp ours.md merged.md && git merge-file merged.md base.md theirs.md   # exit 0 = clean
```

---

## 20. Unity in a worktree: symlink the Library, sandbox the run, carry the metas back

The mechanism that makes per-track Unity runs possible is worth carrying wholesale:

- Each worktree's `Library/` is a **symlink** to the owner checkout's, so `.csproj` references resolve
  and nothing re-imports 3.7 GB per track.
- Test runs never touch that symlink. The runner **rsyncs sources into a per-track sandbox** that owns a
  real copy of `Library` and runs Unity there. First copy is minutes, warm runs about 35 seconds, and
  sibling tracks run concurrently without contending for one project.
- The trap, measured rather than suspected: **`.meta` files are minted in the sandbox, and the sandbox
  is not the repository.** Five new scripts had their GUIDs written into `/tmp/ee-sandbox-track3` and
  into none of the checkout. Unity could see those scripts in the sandbox and not in the repo — which is
  how a test fixture ships invisible. Any sandboxed-Unity workflow needs an explicit copy-back step for
  `*.meta`, or it manufactures the exact defect the project's own rules warn about.
- A fresh worktree has **no `.csproj` at all** — they are gitignored, so `git worktree add` produces a
  tree the compile gate cannot run in. It exits 3 rather than pretending, which is right, but it means
  "compile gate green" is unavailable to a track until a Unity pass has emitted project files there.

---

## 21. Duplicate work is invisible to the agents doing it and expensive the moment it surfaces

Two tracks wrote a spec for the same behaviour, one 139 lines and one 441. Two tracks wrote the same
`TimeScaleService` blend test under two different names. Neither pair conflicted in git — different
filenames, or files that never met — so nothing failed anywhere. The cost is not the duplicated hours;
it is that at integration **nobody can say which one to keep** without reading both, and the person
reading them wrote neither. A short shared "claimed work" list, appended to when work *starts* rather
than when it finishes, is cheaper than either the duplication or the arbitration.

---

## 22. A blocking hook cannot tell an editor's reserialization from a hand-edit

Pioneer's `block-projectsettings.sh` refused to stage `ProjectSettings/TimeManager.asset`. It was right
to by its own lights: those files are Unity-managed. But that diff was Unity 6 itself rewriting
`Fixed Timestep` from a float to a rational of identical value, emitted by a batchmode pass — nothing a
hook can distinguish from someone editing YAML by hand. Left uncommitted it reappears in every worktree
and every agent asks about it. **A hook this blunt is correct as a default and needs a recorded escape:**
the operator decides, and the commit message states that the hook was bypassed and why, so the reasoning
outlives the decision.

The hook also matches on the command *string*, so it blocks a heredoc that merely quotes the phrase it
guards — including the paragraph above, while it was being written. Content-blind pattern matching on
shell commands will fire on documentation about itself.

---

## 23. Piping a gate into `tail` throws away its exit code

Running the test suite as `run-editmode-tests.sh . 2>&1 | tail -40` reported **exit code 0** for a run
that aborted on compiler errors, because the pipeline's status is `tail`'s. This is the same defect
class as the compile gate that could not fail (§1, §8) and the validator that ignored its own findings —
and it appeared here in the *invocation* rather than the script, which is the one place no amount of
hardening inside the script can reach. Read `PIPESTATUS`, or do not pipe a gate.

---

## 24. An error message ran a `git merge`

The compile gate's blind-file-set message contained this line:

```bash
echo "after `git merge hardening/base`, because the merge brings files your projects predate." >&2
```

Backticks inside a double-quoted string are command substitution. The gate did not *print*
`git merge hardening/base` — it **ran** it, every time it reported a problem, and spliced the merge's
output into its own sentence. The tell was the printed text reading "This is the usual state right
after Already up to date., because the merge brings files your projects predate."

A diagnostic that mutates the repository it is diagnosing. On a branch behind the integration branch
it performs a real merge while the reader is being told about stale project files. The class is
familiar from §1 and §8 — a tool doing something other than what it says — but this one *writes*.

**Error-message strings are code.** `grep -n '"[^"]*`[^`]*`' *.sh` is a one-line check for the whole
family, and inside comments it is harmless, so the false-positive rate is low enough to gate on.

---

## 25. The claim list paid for itself in one wave, and the way it failed is the interesting part

A one-line-per-claim file, appended when work *starts*, was added after two tracks wrote the same
spec twice (§21). Within a wave it caught a real collision: one track claimed a finding another had
already fixed and merged. But it caught it **after** the fact, and the note the track left says why:
*"I did not see the claim because it was written after I had already committed."*

That is the honest limit of an append-only file behind a merge — it is only as fresh as your last
pull. It still worked, because the collision surfaced as a written note in a shared file rather than
as two competing implementations discovered by whoever integrated. **Cheap coordination does not have
to be reliable coordination to be worth it; it has to fail visibly.**

---

## 26. A report an agent is told to trust as memory will go stale, and stale "not done" is the worst kind

The model here is: clear the terminal between waves, and let each track's report file be its memory.
It works — but one track's report listed fourteen findings as *not done* that had been done in the
wave in between, and a cleared session reading it would have redone all fourteen against code that no
longer matched the findings being quoted.

The track that found this re-derived every verdict from the source, quoting lines, rather than
believing any report — and then put a banner on the stale table rather than silently editing it.
Both halves matter:

- **A "not done" list decays faster than anything else in a report**, because every other section
  describes what happened and only this one describes what did not — a claim about the *present*,
  written in the past.
- **Banner it, do not quietly correct it.** The banner is what tells the next reader the rest of the
  document may have the same exposure.

---

## 27. Anything a build regenerates in a scratch directory has to be carried back

§20 recorded `.meta` files being minted in the sandbox and never reaching the repository. The fix
that shipped generalises past `.meta`: the sandboxed pass now carries back **both** the `.meta` files
and the four generated `.csproj` files, and says what it carried in the same breath:

```
meta carry-back: nothing new to carry back.
csproj carry-back: refreshed 4 generated project file(s) in <repo>.
```

That second line closes a loop this project spent two rounds on. A fresh worktree has no `.csproj`,
so the compile gate could not run there at all; and after any merge that brings new files the
existing ones are blind. Both are now a single headless pass rather than "open the Editor once".
**The rule: if a gate depends on a generated artifact, the thing that generates it must also deliver
it, and must report what it delivered.**

---

## 28. Two decay patterns a drift test cannot see

Both surfaced in this wave and neither is catchable by "every documented symbol exists":

- **A deprecated shim that documents itself as deletable, still described as live tooling.** The
  script's own header says "DEPRECATED — safe to delete" and prints a deprecation warning; a
  subsystem document still lists it in a table of what to run and what it is for. Every symbol in
  that claim resolves. The claim is still wrong.
- **A baseline that encodes "this number should not drop".** The guidance said a compile-warning
  count far below the recorded baseline means nothing was compiled — a good rule when the baseline is
  current. Then hardening legitimately removed the warnings, and a *correct* gate now reads as blind.
  Baselines that assert a floor rot the moment the project improves past them; they need an owner and
  a refresh, or they teach people to distrust working gates.

---

## 29. A path interpolated into a regex matches things it should not

A guard meant to warn "Unity is already running against the source project" was written as
`pgrep -af "projectPath[= ]$SRC\b"`. Every prompt in the wave invoked the runner as
`run-editmode-tests.sh .`, so `$SRC` was `.` — which, in a regex, matches any character. The guard
fired whenever *any* Unity was running anywhere.

Advisory only, so nothing broke; but it is noise on exactly the message that would matter when it is
real, which is how a guard trains its readers to ignore it. **Interpolating a path into a pattern is
a bug unless the path is escaped or the match is anchored** — and `.` is the single most likely value
in a tool that takes a directory argument.

---

## 30. Never gate on a warning count; gate on a keyed ceiling

The recommended practice, written into this toolkit's own guidance, was to record a per-project
compile-warning count and treat a number far below it as evidence that nothing was compiled. Three
measurements retired it, and they generalise past this project:

1. **The recorded numbers rot downward because the project improves.** Every cleanup that removes an
   unused using makes the floor fire.
2. **A per-project "N Warning(s)" is not a property of the code at all.** It is the sum over that
   project and everything msbuild rebuilt underneath it, so it depends on build order and cache
   state. Same tree, same sources, three different answers — sequential into a shared empty obj dir,
   each project rebuilt in isolation, and a warm second pass — and two consecutive runs of the *same*
   loop disagreed with each other. No floor can be stated for a number that is not stable.
3. **The thing the rule was a proxy for is better done structurally.** A gate that deletes its own
   scratch directories before building cannot produce an incremental no-op, so it does not need a
   human to remember to clean-build. Measured cost: 12.0s clean against 10.5s warm for four projects.

What replaced it is a **ceiling keyed by file and warning code**, not by line number, so ordinary
edits do not churn it. A new or more-numerous warning fails. A warning that has been *fixed* does not
fail — it prints a line asking you to delete the entry.

That asymmetry is the reusable part: **a gate that fires when the project gets better is a gate people
learn to ignore.** The floor rule had already trained one reader to conclude a working gate was blind.

---

## 31. An incremental no-op build reports a clean bill of health

`0 Warning(s), 0 Error(s)` is what a build prints when it decided there was nothing to do. It is
indistinguishable from a clean compile of everything, and it is the second-cheapest way this project
found to make a gate lie (the first being a stale `.csproj`). A build gate should delete its own
`obj`/`bin` scratch directories before it starts. It is worth about a second and a half.

---

## 32. Guards need their own tests, because all three failure modes look like silence

After the `.`-as-regex bug, the fix came with a committed self-test — eleven cases run against fake
processes — and its header makes the argument better than an abstraction could: a guard that decides
whether Unity may run against a directory can be wrong in three directions, and **none of them is
visible by reading the function.**

- Permissive: corrupts a 3.7 GB `Library` four worktrees share.
- Restrictive: blocks a run that had no conflict.
- Advisory-but-always-firing: trains everyone to ignore the one message that matters.

The evidence that this is not over-engineering: the *rewritten* guard failed three of its own cases on
first run — it matched the test harness's own shell, and it read only the first `-projectPath` on a
line carrying several. Both were found before the commit rather than after a corrupted Library.

**Any check whose output is "nothing" when it passes should have a test that makes it say something.**

---

## 33. Tier a gate by what it needs, and make it say which tier ran

The batch-tool gate runs source-level assertions with no Unity and no licence in about a second — that
tier runs in cloud CI — and optionally spawns Unity per tool to read the real exit codes. It prints
`PASS (STATIC only)` or `PASS (STATIC + FULL)`.

This is the shape for anything licence-gated or slow: the cheap tier is honest about being cheap, so
a CI badge means what it says, and the expensive tier is available locally without a second script to
maintain. Compare the failure it avoids — a single-tier gate that silently degrades to the cheap
checks and still prints PASS.

---

## 34. Writing the operator's steps is what finally measures the finding

The worklist for editor-only work (§ the Developer Action Items pattern) produced seven entries in one
wave, and the first one **corrected the finding it was written for.** The finding claimed the data sat
"across 17 build scenes"; writing executable steps forced someone to look, and it was five assets, two
of them shipping. Two other entries recommend *not* doing the work, with the cost of each option
stated.

That is the argument for the file beyond convenience: a finding can sit in a backlog for three waves
carrying an unmeasured number, because nothing forces the measurement until someone has to write
"open this asset, change this field". Requiring "which asset, which menu, which field, what to verify"
is a measurement requirement disguised as a formatting rule.

The rule that makes it work: **"the operator should decide about X" is not an entry.** State the
options with costs and recommend one, so the operator decides rather than researches.

---

## 35. Shared append-only files need a merge convention, not just a format

Two tracks independently wrote an "Entry 5" into the operator worklist in the same wave; the merge
kept both and renumbered one. The same file had already produced a claim collision where one track
claimed work another had finished, because an append-only file is only as fresh as your last pull.

Both are cheap to fix at the integration point and impossible to prevent at the authoring point, so
the convention matters more than the format: **number nothing that two writers can number
simultaneously**, or accept that renumbering is part of merging and say so in the file. Sequential IDs
in a file with concurrent writers are a distributed counter, and nobody treats them like one.

---

## 36. The documentation structure this project needed, and the one Pioneer ships

Pioneer has three documentation folders, and every one of them is forward-looking:

| Folder | Written by | Used in Endless Evolution |
|---|---|---|
| `docs/design/` | the eight design agents, `/brainstorm`, `/design-system` | **not at all** |
| `docs/production/` | `/sprint-plan`, `/milestone-review`, `/retrospective` | **not at all** |
| `docs/adr/` | `technical-director` | **not at all** |

Zero of three, across a day that produced 17,316 lines of documentation. That is not a criticism of
the design layer — it is the correct outcome for the job. Those folders describe a game being
designed. This was an existing codebase being understood, and **Pioneer has no slot for
reverse-documenting code that already exists.**

### What the project already had, and what we did to it

A pre-existing `AGENTS.md` layer: one at the repository root acting as a domain-routing table, plus
one per subtree — twelve in all. We kept it. Four were deleted, all covering directories with no
first-party logic (`Sprites/`, `TextMesh Pro/`, `URP Settings/`, and one whose contents moved). The
rest were barely touched: the root grew 171 → 210 lines, `Assets/Core/` 94 → 95, `Assets/Enemies/`
47 → 47.

On top of it we added a layer that did not exist: **`docs/systems/`** — 21 documents, 8,926 lines, one
per subsystem, each answering the same four questions.

1. What does this own — the state it is authoritative for.
2. What may I call, and what must be true first — the real public surface, found by grepping call
   sites, with preconditions. **Not a generated member dump.**
3. What breaks if I change it — callers and callees by filename, in both directions.
4. Which numbers are somebody's tuning decision — the hand-tuned values and the gotchas already paid
   for in debugging time.

The division of labour is stated in the entry point rather than left to be inferred: **the routing
table gets you to the folder, the subsystem document gets you to the contract, and both layers are
maintained — neither replaces the other.**

### The thing that actually made the difference, and it is not the shape

Only one of those two layers is machine-checked. `DocumentationMapSpec` has an explicit map set —
`docs/systems/` plus five root documents — and resolves every `Type.Member` citation in it by
reflection over the loaded assemblies. **`AGENTS.md` is not in that set.** No test verifies a single
claim in it.

The difference showed up immediately and in both directions:

- The moment the map test gained reflection it found real drift in the checked layer: a flag
  documented as `BlockChase` that the code calls `BlocksChase`, and a `Detach()` method the docs
  described that no longer existed.
- The unchecked layer carried a wrong diagnosis for two full waves. The root `AGENTS.md` claimed 69
  missing script references with "shared prefab suspected". The count was right; the diagnosis was
  wrong — they are hand-placed components, not one prefab's instances — and nothing could tell anyone,
  because prose about a *suspicion* has no symbol to resolve.

So the transferable claim is narrow and strong: **a documentation layer is worth what its verification
is worth.** Shape helps a reader; only a test keeps a document true. Everything else decays at the
speed of the code.

### Two design details worth copying

- **Exempt the history explicitly, and say why.** `docs/hardening/**` and the change log are
  deliberately outside the map set: they cite files that were correct when written and have since been
  deleted, and rewriting history to satisfy a test would destroy exactly what makes it useful. A drift
  test without an exemption category forces you to choose between a green suite and an honest record.
- **Give the escape hatch a syntax.** A document that must cite something which does not exist —
  describing a deletion, or quoting a finding about a name that was always wrong — declares it inline:
  `<!-- map-check: allow-missing <path> -->` and `<!-- map-check: allow-name <symbol> -->`. Without
  that, the first legitimate exception teaches someone to disable the check.

### What this suggests for the toolkit, when we get to it

Not a proposal yet — a note of what the evidence supports:

- Pioneer would benefit from a **brownfield documentation slot** alongside the design-first three.
  `docs/systems/` earned its place here: every track read it, and it is what the prompts pointed at.
- The **drift test matters more than the template.** If only one of the two ships, ship the test.
- The ADR slot did not attract the decisions it was built for. Architecture decisions in this project
  landed in `docs/hardening/cross-unit-notices.md` — a cross-track proposal file with a status field —
  because that is where the conversation was, and a decision written next to the work is written and a
  decision written into an empty folder is not. Worth understanding before prescribing `docs/adr/`
  harder.
- Minor but real: `.claude/` was gitignored in this project, so the toolkit that ran the work was not
  versioned alongside it. That turned out to have a cause worth its own section — see §37.

---

## 37. A blanket `/.claude/` predates the toolkit, and the installer reads it as consent

`install.sh` asks git whether three specific paths are already ignored, and if they are, leaves the
project's `.gitignore` alone. The comment explaining it is good manners and says so plainly: a project
that ignores `/.claude/` wholesale is "a perfectly sensible choice, and one real projects make", so
appending our entries would be "just noise in someone else's file".

In Endless Evolution the wholesale line was added on **2026-06-10**. Pioneer was installed on
**2026-07-30**. The line was written seven weeks before there was any toolkit to have an opinion
about — by someone ignoring the settings file of a different tool entirely.

The measured consequence: **179 files and 27,905 lines** — every agent, command, skill, hook and rule
the hardening waves ran under, plus the provenance manifest recording what each vendored file is —
existed on exactly one disk for the whole engagement. Every gate those waves built is reproducible
from the repository. The thing that built them was not.

The check conflates two different questions:

- *Is the machine-specific local state ignored?* — Yes, and that is all `check-ignore` can answer.
- *Has this project decided how to version the toolkit?* — Unanswerable from a line that predates it.

The fix is not to edit someone else's `.gitignore`; leaving it alone is still right. It is to **say
what it implies**, once, at install time: `/.claude/` is ignored wholesale, so the agents, commands,
skills, hooks and rules being installed will not be versioned with the project — and here is the
narrower rule if that is not what you want.

### The checklist for actually tracking it, because this is a quiet way to blind a gate

Committing `.claude/` in a Unity project is safe, but only after five checks, and four of them are
the kind that fail silently:

1. **No `.cs` anywhere under `.claude/`.** A compile gate that asserts "every tracked first-party
   `.cs` appears in a project it builds" goes blind the moment a tracked `.cs` exists outside the
   assembly graph. (Note how the operator-tools directory in this project ships an editor script as
   `.cs.txt` for exactly this reason.)
2. **It is outside `Assets/`**, so Unity neither imports it nor wants `.meta` files for it.
3. **It is outside the documentation drift-test's map set**, or every path cited in a skill becomes a
   claim the suite must verify.
4. **No absolute paths or usernames in the tracked files** — the hook commands must be repo-relative,
   or a collaborator's clone gets hooks pointing at your home directory.
5. **The hook scripts keep mode `100755`.** Git preserves the executable bit, but only if it was set
   when they were added; a fresh clone with `100644` hooks fails in a way that reads as "the hook did
   not fire" rather than "the hook could not run".

What stays ignored, and now for a stated reason rather than a blanket one: the local settings file
(per-machine MCP enablement), `state/*` (session state and the install receipt, which carries machine
paths), and the scheduled-tasks lock, which holds a live session id and pid.

---

## 38. Six green gates, and none of them built the game

166 commits landed in one day behind a gate stack that grew from nothing to six checks: source
layout, missing-script resolution, a runner guard self-test, a batch-tool exit-code gate, a compile
gate with a file-set assertion and a warning ceiling, and 600 tests across EditMode and PlayMode. All
six green. **No player build existed, and nothing had ever produced one.**

The common property is easy to miss while you are building them one at a time: **every gate read the
source tree, and none read the artifact.** `dotnet build` over Unity's generated `.csproj` files is
the strongest of them and it is still the *Editor's* view of the world — those projects reference the
Editor assemblies. The class of defect it cannot see:

- runtime code reaching `UnityEditor`,
- an asmdef whose platform list excludes the target,
- a `#if UNITY_EDITOR` block that turned out to be load-bearing.

All three compile cleanly and all three are fatal to a build. And the two changes most likely to
produce one landed on exactly the day the gate did not exist: assembly definitions were introduced,
and two editor-only classes were moved out of the player build behind an asmref.

The fix is a `-executeMethod` entry point that calls `BuildPipeline.BuildPlayer` and gates on the
result, wrapped in a runner that spawns it and reads `$?`. Three details earned their place:

- **Treat a `Succeeded` report of zero bytes as a failure**, and an empty scene list as a failure
  rather than a harness problem. A player built from no scenes succeeds and ships nothing — the same
  green-but-meaningless shape as a compile gate that compiled nothing (§1) and a validator that
  ignored its own findings.
- **Keep it out of the pre-commit/pre-push path.** A build is minutes. A gate that makes `git push`
  take five minutes is a gate people bypass with `--no-verify`, and a bypassed gate is worth less than
  no gate because it still reads as coverage.
- **Give it its own sandbox.** A build writes into `Library`; sharing the test sandbox makes builds
  and test runs evict each other's warm caches, turning a 35-second suite back into minutes.

Verified in both directions before it was believed, which is the standard the rest of this stack is
held to: `StandaloneLinux64` produced a 167 MB player from 36 scenes in 1m40s, and a target whose
module is not installed came back `result: Unknown`, 0 bytes, exit 2, printing the reason rather than
the code alone. **A gate nobody has watched fail is a hypothesis.**

### The general form, for the toolkit

The question to ask of any gate stack is not "how many checks" but **"which of these reads what I
ship?"** A stack can be arbitrarily thorough about sources and still be silent about the artifact.
For Unity specifically, that means a player build; the equivalent elsewhere is whatever the user
actually receives.

---

## 39. Four agents ran a full night with nobody awake, and one rule is why

Every previous wave assumed an operator: relaying between sessions, answering the question a blocked
track asks. The overnight wave removed that, and the model held — 88 commits, +10,006 lines, four
branches merged, all gates green in the morning.

The rule that carried it is one sentence: **never wait, never ask — write the block down and take the
next item.** It came with a file to write into, and the file is what makes it real; "move on" without
somewhere to put the thing you moved on from just loses it.

The evidence that it worked is not that the file was empty. Three blocks were filed. One was resolved
by the same track before the night ended, which is what a track does when stopping is not an option.
One was a genuine decision only the owner can make — a serialized value that disagrees with its code
default across 79 instances — and the track wrote it up, wrote its test to *read* the field rather
than assume either number, and kept going. Nothing waited.

Three supporting rules, each earned rather than invented:

- **Run the gate yourself before merging.** `pre-push` is a *push* hook, and merging a local branch
  into a local integration branch never fires it. Under supervision the operator and the integrator
  caught what discipline missed; unattended, discipline is the whole mechanism, so it has to be said
  out loud in the prompt.
- **Two failures on the same unit and you abandon it.** Bounds the worst case: a track that burns the
  night on one finding produces nothing.
- **Append to your report after each unit, not at the end.** A session that dies at hour five with
  everything in context and nothing on disk has lost the night. Thirty-four small merges, each
  preceded by a merge from base, is what this produces — and it is also why nothing had to be
  untangled in the morning.

---

## 40. "Blockers expire" is true, and the reason they expire is not the one you plan for

The overnight wave was organised around an idea: the richest work available is not new, it is work
recorded as impossible for a reason that has since stopped being true. A report said in as many words
that PlayMode was unavailable so two state machines were out of reach; PlayMode had since arrived.

The idea paid — but the track that tested it hardest reported back that the *premise* was wrong. Of
seven recorded declines re-decided, three had expired and **only one expired because a new capability
arrived**, which was the stated premise of the whole wave. The other two expired because the work had
been done elsewhere in the meantime, and because an **ownership boundary moved** — a decline whose
stated blocker was "those files belong to another track this wave", which was never technical at all.

Three of the seven still held, two of them more strongly than when written.

So the generalisation is not "wait for the capability, then revisit". It is: **a recorded decline
decays for reasons unrelated to why it was recorded, so re-reading your own declines is worth a slot
every wave regardless of what changed.** And a decline that survives re-examination is a real result
worth writing down again — three of seven here — not a failed attempt at work.

---

## 41. Mutation-testing the gates found one blind to 29% of what it policed

Six gates existed; two had ever been watched to fail. A night spent breaking each one on purpose
found defects in three, and the largest was invisible by every other means:

**The source-layout gate never saw 49 of 171 first-party files.** Its banned-construct checks ran
through `git ls-files '*.cs' | ... | xargs -r grep`, and `xargs` splits on whitespace, so
`Assets/Core/Save System/SaveManager.cs` arrived at `grep` as two paths that do not exist. Every
missed file lived under a directory whose name contains a space: `Save System`, `DNA Forms`,
`Input UI`, `World Level`. Three deliberate violations sailed through before the fix.

**Any gate that consumes a file list must be tested against the most awkward names in the repository**,
and in a Unity project that means directory names with spaces — Unity's own conventions produce them.
A gate tested only against `Player.cs` is tested against the easy half.

The same pass found a defect class no review catalog covered: **seven batch entry points could return
without ever reaching `EditorApplication.Exit`**, because each wrote its log with a relative path
outside any `try`, immediately before the exit it had already computed correctly. A tool that computes
the right verdict and never delivers it is indistinguishable, to a shell caller, from a tool that hung.

---

## 42. The comment was right and the code was wrong, and only a mutation found it

A gate written the day before carried a comment stating that an unparseable environment override "is a
failure rather than a silent fallback, because the alternative is to build a platform nobody asked for
and report success". Two lines below, the code did the silent fallback the comment disclaimed.

Nothing catches this. The compile gate compiles it, the tests pass, and a reviewer reads the comment
and believes it — the comment is more persuasive than the code precisely because it explains the
intent. It surfaced only when someone set the variable to a deliberately wrong value to see what would
happen.

**When a comment states a policy, the mutation that tests the policy is the cheapest way to find out
whether the code implements it.** Worth a habit: after writing a comment that says "X is a failure",
make X happen once.

---

## 43. A count is not a record, and the count is what survives

A wave was planned around a backlog of findings. The plan quoted the one previous audit of that
backlog — a per-catalog table of how many findings were applied, open, or "catalog itself wrong" — and
built its method on the third column: nine of fifty-nine findings described code that did not exist,
so "the catalog is wrong about itself" was declared a real and common verdict and every track was told
to expect it.

The track whose audit produced that number re-derived it and **withdrew it**. Two independent
read-only agents, each required to quote the line it read, found **zero** findings whose subject does
not exist. The nine were wrong *sub-claims inside findings whose conclusions were sound* — mostly
miscounted footprints. One of them miscounts the null entries in its own evidence while describing a
defect that is entirely real and still needs fixing.

The distinction is not pedantic, because the two verdicts imply opposite actions: *finding wrong*
closes the work, *evidence wrong* keeps it open and fixes the quote. Planning from the first would
have closed real defects.

The sentence that generalises it is theirs:

> The count survived my audit and the per-id verdicts did not, so **the one artifact of that audit
> that reached this plan is the part that was wrong. A count is not a record.**

That is the shape to carry:

- **A summary is what survives an audit, and it is the least reliable thing the audit produced.**
  Per-item judgements live in the agent's context and die with it unless they are written down; the
  tally gets copied into the report, then into the next plan, then into a prompt — gaining authority
  at every hop while losing the evidence that would let anyone check it.
- **If a wave's plan quotes a number from a previous wave, that number is the thing to re-derive
  first**, not the thing to build the method on.
- **The fix is a record with one row per item and its evidence**, which is what this project then
  built: a ledger keyed by finding id, a status per row, and a gate that fails when a row claiming
  "applied" cites evidence that no longer resolves. `unknown` is a permitted status, so honesty about
  what nobody has checked is cheaper than a guess.

One methodological detail worth stealing: the audit that settled it re-read the **pre-fix revision**
for findings that had since been fixed. A finding is not wrong because the code changed under it, and
an auditor comparing an old claim against new code will report false "catalog wrong" verdicts all day.

## 44. The record was built, and the audit still landed as a paragraph

§43 ends with the fix: a ledger with one row per finding and a gate over it, `unknown` permitted so
that honesty about what nobody has checked is cheaper than a guess. It shipped. One wave later the
ledger reported **129 ids as `unknown`** — and every one of them had been audited that same night.

The audit was real work, done well: one read-only agent per catalog, each required to quote the line
it read rather than cite it, every "cannot be pinned" verdict re-decided against today's capability.
The output was a 129-row table with evidence, in the track's own report file. It never became 129
ledger rows, so the gate — correctly, by its own rules — counted the whole thing as unaudited.

The track that built the ledger had already written the sentence, in the never-block channel, and
nobody acted on it before the wave ended:

> The audit's deliverable is a **ledger row**, not a paragraph.

What this adds to §43:

- **Building the record does not migrate the work into it.** §43's lesson is that a tally is not a
  record; this one is that a *rich, evidenced, per-item report* is not a record either, if the
  machine-checkable file is somewhere else. The report is still a paragraph — a long one.
- **State the deliverable as the artifact the gate reads, in the prompt, before the work starts.**
  "Audit your six catalogs" produced a report. "Produce a ledger row per id" would have produced
  rows. The agent optimised for the deliverable it was given, which is what you want it to do.
- **A gate that reports coverage will tell you this happened.** That is the payoff for making
  `unknown` a first-class status rather than a failure: the gap was one `awk` away, on a file
  designed to be read, instead of being discovered two waves later by someone re-doing the audit.

The transcription is not free, either, and the reason is a good one. The report cites `File.cs:445`
plus a quote; the ledger's evidence grammar is deliberately line-number-free (`grep:<path>::<needle>`)
because *a baseline keyed by a line number is a baseline nobody updates*. So the transcription is
partly a re-verification, and each row that fails to resolve is a verdict that was wrong when written
or has been overtaken since. Which is the point.

## 45. A backlog can grow because your capability grew, and that is not scope creep

The same audit returned **100 of 129 findings open** — where the previous wave's audit of a different
subsystem had found the opposite, most of its findings already applied. Two audits, same method,
opposite results. The reason is in the auditing track's own method section:

> Every "cannot be pinned" verdict was re-decided **against today's capability**. Findings were
> classified "report only / not automatically testable" in waves when this repository had no PlayMode
> tier at all.

The tier now existed — a real physics rig, live fixtures, a mutation harness. Findings closed as
untestable were open again, not because anyone changed their mind about the code, but because the
ground moved under the verdict.

Three things to carry:

- **"Cannot be tested" is a dated claim, and it should be stored with its date and its reason.** A
  verdict that names the missing capability ("no PlayMode tier") can be re-decided in one grep the day
  that capability lands. A verdict that just says "not testable" is permanent by accident.
- **A growing backlog is not automatically a failure.** It can mean the net got finer. The number to
  watch is not the count of open findings but whether closing one now costs less than it did.
- **Sequencing follows from this.** Build the capability, *then* re-audit — the reverse wastes the
  audit. Had the re-decision pass run before the rig existed, it would have re-confirmed every
  "untestable" verdict at full cost and produced nothing.

## 46. Give the risky dependency a time box, not a fallback plan

A wave needed Editor work that only a live tool bridge could do, and the bridge had never been used
in anger. The instinct is to write a fallback: if the bridge fails, do X instead. The rule that
actually worked was smaller — **make it the first unit and put a clock on it.**

> This unit is time-boxed to about 85 minutes. When the box runs out, or the bridge drops, or the
> editor reloads mid-call, or any single entry fails twice — write down where you got to and move to
> unit 2.

Why the box beats the fallback: a fallback is a decision the agent has to make while it is invested in
making the thing work, which is the worst moment to ask. A box is a decision already made. And the
cost is bounded in the unit the risk lives in — an unproven dependency costs one unit, not one
session. It is the never-wait rule (§ *file it and take the next item*) applied to a dependency
instead of to a question.

Two supporting details that mattered as much as the box:

- **Smallest entry first, largest last.** The largest touched 88 scene files. Ordering it last meant
  the agent's competence with the bridge was demonstrated on cheap work before anything expensive
  moved, and the reviewer's biggest diff arrived from a process already proven that session.
- **Say out loud which guard is not in force.** The repository's "agents do not edit scenes" hook
  matches on the file-editing tools by name and structurally cannot see tool-bridge calls. So for the
  duration of that unit the guard did not exist. Writing that into the prompt — *you are working
  without a net, behave as though it were there* — is worth more than pretending the hook covers it.

## 47. A listening port is not an attached tool, and a worktree is a different project

The wave in §46 was planned around a live tool bridge. The bridge was verified before the wave
started: the server answered on its port, and the CLI's own `mcp list` printed **✔ Connected**. The
agent that was given the work opened its session and had **no bridge tools at all**.

Both checks were true and neither was the right one. The port proves *a server is listening*. The
tool list proves *the current directory's config resolves the server*. Neither proves **this session
attached it at start-up**, and only that last one lets an agent call anything. The agent's own note
is the sentence to keep: *check the session's MCP config, not the port.*

Two mechanisms conspired, and both are worth knowing before trusting a bridge to a fleet:

- **A project-scoped `.mcp.json` needs approval.** The file was present, correct, and committed. It
  is not loaded until someone answers the "use this MCP server?" prompt for that project, and the
  approval lives in the user's own config keyed by directory. An unanswered prompt looks exactly like
  a missing server.
- **Each git worktree is a different project directory.** The fleet ran in four worktrees. Approving
  the server in the main checkout — the directory where the verification was done — approved it in
  none of the four places the work happened.

The fix that survives both is a **user-scope registration** rather than a per-project file, because
it needs no per-directory approval and worktrees inherit it. The general rule: **verify a dependency
from inside the process that will use it, in the directory it will run in** — not from the operator's
shell in the repo root.

## 48. The agent found the second route to the Editor, and it was already in the repo

What makes §47 a good story rather than a lost session: the agent did not stop at "MCP is
unavailable, filing it, moving to unit 2" — which is what the prompt licensed it to do. It observed
that a bridge is only one way to reach a Unity Editor from an agent, and that **this repository
already drove a headless Editor on every push** — a sandbox copy plus `-executeMethod`, built for
the test gates. Same Editor API surface, different transport.

So the five Editor entries were re-routed instead of deferred, and — the part worth stealing — the
**ordering was re-derived under the new cost function.** The plan had said smallest-first, and had
computed "smallest" in bridge round-trips. Under batch mode the cost is different: anything needing a
Unity pass costs minutes, anything not needing one costs seconds. The agent reordered to run the
three no-Unity entries first and the two Unity-pass entries last, and wrote down that this *preserves
the plan's intent* under the mechanism actually available.

That is the distinction between following a plan and executing one. A plan's ordering is usually a
proxy for a cost the plan names; when the mechanism changes, re-compute the proxy rather than
inheriting the order.

Two caveats it also recorded, both honest:

- **The route does not cover everything.** Several verification steps were *"enter play mode and
  confirm the water still ripples"*. No automated check in that repository loads a scene. The agent
  ran every mechanical check, pasted the output, and listed the visual ones as outstanding — with the
  line that settles how to read the result: **"an argument is not an observation."**
- **A guard that names a tool cannot see a different tool.** The hook stopping agents from editing
  scenes matched on the file-editing tools by name. It could not see bridge calls (§46) and it could
  not see `-executeMethod` either. The route around it was legitimate and the hook was still blind.

## 49. The worklist entries were right about the code and wrong about the tooling

Executing five long-deferred Editor entries found **six errors in the entries' own instructions**, and
four of them would have failed a gate. The pattern the agent extracted is sharper than the list:

> An entry's measurements were reliable about the **code** and unreliable about the **tooling**. Every
> wrong claim was about what a gate or the Editor would *do*, not about what the source says.

The concrete shapes, all of which generalise past Unity:

- **A deletion invalidates evidence that lives inside the deleted thing.** Rows proving a fix by
  "this file does *not* contain X" all broke, because that form requires the file to exist. Six more
  proved a claim from a GUID stored in the asset's own sidecar, which went with the asset. If your
  record cites a file, deleting that file is a record migration, not just a deletion.
- **"Open it in the editor and save it" is a guess about the editor.** It was written into an entry as
  a verification step. Measured, it stripped nothing — the tool deliberately *preserves* an override
  whose target no longer resolves. It needed a specific API call. Steps that describe editor
  behaviour should be executed once before they are written down as steps.
- **A dependency claim measured against a hand-written list of names is measured against the list.**
  An entry claimed a file move had zero outbound dependencies; the file called a type the nine-name
  list omitted — the one type the entry's own closing paragraph said must stay behind. The layer gate
  caught it. Derive the list, do not curate it.

The forward-looking version, for anyone writing work for an agent to execute later: **the parts of a
task description that describe your tools are the parts most likely to be wrong**, because they were
written from memory while the source claims were written from the source.

## 50. Three waves reasoned from an incident log, and the incident log only records failures

A fleet's tracks each merge their branch into a shared integration branch when a unit goes green.
Three separate tracks, in three separate waves, hit the same wall: the merge command was refused by
the harness's permission classifier. Each filed a careful entry. Each concluded the same thing:

> the classifier is refusing the **action**, not the syntax

From that premise, remedies were proposed and debated across three waves — an integration script,
twice proposed; then declined by the track that owned it, on reasoning that was internally excellent:
*a script is the same command in the same directory, so it is either refused identically or "works"
only by being unrecognisable, which is routing around a denial.*

The premise was false, and one command falsified it. The integration branch's **reflog** records every
merge that ever landed:

| track branch | successful merges |
|---|---:|
| 1 | 12 |
| 2 | 22 |
| 3 | 18 |
| 4 | 13 |
| **total** | **65** |

Sixty-five approvals against three refusals of the same command — **twelve of the approvals belonging
to the very track that concluded the action was categorically refused.** The classifier is a model
making a per-invocation judgement; the wall was the tail of a distribution. One of the refusals even
said so in its own error text (*"usually transient — retrying often succeeds"*), which three careful
readers read as a policy statement.

The mechanism is worth naming precisely, because it will recur everywhere agents keep incident logs:

- **Failures get written down and successes do not.** Every refusal produced a 40-line entry with
  evidence. Every one of the 65 successes produced nothing but a merge commit that looked like
  routine progress. Any rate inferred from the incident file is therefore not just imprecise, it is
  *unboundedly* wrong — the denominator was never recorded there at all.
- **Each entry cited the previous entries as corroboration.** Three independent observations of the
  same event felt like mounting evidence for a rule. They were three draws from the same tail. The
  third entry is the most rigorous of the three and reaches the most confidently wrong conclusion,
  because it had two prior entries to agree with.
- **Every proposed remedy was designed for the wrong failure**, and the best reasoning in the whole
  sequence — the refusal to write the script — was sound *given* the premise and irrelevant without
  it. Careful thinking downstream of an unchecked premise produces confident, useless output.

The corrections, both cheap:

- **Find the denominator before theorising about the numerator.** The reflog took one command and
  ten seconds. Ask, of any "X is blocked" claim: *what would the record of X succeeding look like, and
  have I looked at it?* Git reflogs, shell history, CI history, and commit logs are all denominators
  that nobody thinks to open because they are not where problems are filed.
- **If a failure is variance, the fix is a retry policy, not an architecture.** The operative rule
  became: *a refused merge is a delay, not a stop — retry at the start of the next unit, and file it
  only after three refusals.* That is free, requires no permission change, and converts a hard stop
  into a bounded delay. Three waves of design work were spent avoiding it.

One coda that is not incidental. The genuinely correct fix — an explicit allow rule, so the
classifier is never asked to guess — was attempted by the agent writing this up, and **refused**.
That refusal was right: an agent widening its own permissions is privilege escalation whatever the
justification. The deterministic half of the fix belongs to the human, by design, and only the retry
policy belongs to the fleet.

## 51. Every gate assumed it was the only thing running, and four of them were wrong

A four-agent fleet ran its test suites in four isolated sandboxes — separate directories, separate
result files, separate build outputs, all deliberately namespaced per track. Two gates still failed
intermittently, and the cause was a piece of state nobody had namespaced because nobody owned it:
**the engine's own per-user data directory.**

Unity's `Application.persistentDataPath` is keyed by *company name and product name*, not by project
path. Four sandboxed copies of the same project therefore resolve to **one** directory. A guard that
fingerprinted that directory at setup and compared at teardown could not tell one of its own specs
from another Unity process writing during its window.

The track that found it established the cause by controlled experiment rather than by argument — same
tree, twice:

```
concurrent PlayMode elsewhere  ->  219/219 pass, guard FAILS
nothing else in PlayMode       ->  219/219 pass, guard passes, exit 0
```

And then wrote the sentence that makes it worth a field note:

> **The false positive is the lesser problem.** The same fact means four tracks read and write one
> another's save files in every run. Do not weaken the guard; stop the sharing.

The second failure was the same defect wearing different clothes: a probe hung its timeout under
load, was killed, and the kill surfaced as a *different* gate reporting "another process held the
project open". Two red gates, one cause, and a reader taking them as independent would go hunting a
defect in the wrong subsystem entirely.

What to carry:

- **Isolate by identity, not by path.** Sandboxing a working directory is the easy half. Anything the
  runtime keys by *product identity* — user data dirs, registry keys, named pipes, lock files, ports,
  OS-level caches — is shared no matter how many copies of the tree you make. Enumerate those before
  running anything in parallel, not after it flakes.
- **A flaky gate has two costs and the visible one is smaller.** The false positive wastes a cycle.
  The shared state it reveals was corrupting real runs the whole time, silently. Chase the cause even
  when the symptom is "just a flake".
- **Under parallelism, one failure can manufacture another.** When two gates go red together, check
  whether the second is a consequence before treating it as a second bug.
- **Prove concurrency bugs by running the concurrency.** One experiment with and without a
  neighbouring process beat any amount of reading, and it is two runs.

## 52. A mutation harness must restore what was there, not what is in HEAD

A track needed to mutation-verify a fix, found the shared harness hardcoded to the wrong test
platform, and hand-rolled a substitute for one unit. Reasonable — except the substitute silently lost
three properties the real harness had *by construction*, and all three were caught only because the
track kept checking its own work:

1. **It restored with `git checkout -- <file>`.** The fix under test was uncommitted, so the very
   first restore reverted the fix itself, and every subsequent mutation would have run against
   pre-fix code — reporting green for a harness that was measuring nothing. The line to keep:
   **git restores to `HEAD`; a mutation harness must restore to what was there.** Save the original
   text and put it back.
2. **Two mutations each changed two things at once**, so neither could say which assertion caught it.
   The real harness models an expected-failure list per mutation and reports IMPRECISE when the wrong
   test goes red; a script that only prints failures cannot.
3. **A decorative test survived a mutation and was scored as catching it**, because the mutation
   reddened a *different* test in the same fixture. Only an explicit per-mutation prediction
   distinguishes "caught" from "something went red".

The generalisable point is not about mutation testing. It is that **a purpose-built tool encodes
invariants that are invisible in its output**, so a hand-rolled substitute passes the same surface
check while guaranteeing none of them. Before replacing a tool for one job, ask what it does that you
would never think to do — and if you cannot answer, read its source, not its interface.

The track's own resolution is the right instinct too: it did **not** patch the shared harness at the
end of a unit, because that is tooling all four agents run inside their push hook and the change
would land in someone else's night. It hardened its own script, filed the fix with the design
already worked out, and left the shared change to whoever owns a tooling unit. **The right fix at the
wrong moment is still the wrong change.**

## 53. The first gate that loaded a scene found three things only running it could find

An agent was given one task for a whole session: build the check that nobody had built, because two
consecutive waves had ended with the same sentence — *no automated check in this repository loads a
scene*. What came back is the best argument in this whole log for spending a session on one thing.

The harness itself is unremarkable in description: enumerate the scenes in the build settings, load
each, assert nothing logs an error, assert no component failed to bind. What could not have been
written from a desk:

- **Under headless batch mode, the renderer's 2D tilemap path segfaults the engine outright.** Not an
  exception — signal 11, process gone. The only workable placement for the fix (disabling cameras)
  turned out to be a persistent guard's late-update, because a scene can activate in a frame the test
  coroutine does not own. The consequence is stated in the file header rather than discovered later:
  **this gate cannot prove a scene renders.**
- **It cannot live in the existing suite.** Loading a real scene bootstraps the real service root,
  whose objects survive scene changes, and several existing specs open by asserting no such singleton
  is alive. So the suite excludes the new category explicitly, and the header records that removing
  the exclusion turns the suite red.
- **Two real defects on the first working run**, reported rather than failed, because this gate's
  claim is about loading and not about unloading.

Three details worth copying wholesale:

- **The design decisions live in the file header with their reasons** — how many frames to settle and
  why, warnings counted but never failed, one accumulated report per scene instead of throwing at the
  first problem. These are exactly the knobs a later reader would "tidy" into a flaky gate.
- **The blind spot is permanent and documented.** Mutation-verifying the gate found one break it
  cannot see (the engine silently discards the dangling reference), and that was written down as a
  blind spot rather than quietly dropped or papered over. **A gate that states what it cannot see is
  worth more than one that implies it sees everything.**
- **It is wired conditionally.** 36 scenes cost 55 seconds, so it runs in the push hook only when the
  push touches a scene, a prefab, or the build settings, and on demand otherwise. The rule that keeps
  gates alive: never make the common path slow enough that someone starts skipping it.

## 54. Six reviewed tasks, and every defect found was in the spec rather than the work

A plan was written and then executed by fresh subagents, one per task, with an independent reviewer
after each and a whole-branch review at the end. Six implementer dispatches, six task reviews, four
fix rounds. **Every single defect found was in the plan, not in the implementation.** The implementers
transcribed faithfully; the reviewers caught the author.

The list, because the pattern only shows at full length:

| what was wrong | who caught it |
|---|---|
| "fourteen free layer slots" — actually thirteen | task 1's implementer, before committing |
| "27 hooks" — actually 26; the 27th file is a sourced library | task 3's reviewer |
| a batching rule that let a semantic judgement through as a textual one | task 4's reviewer |
| verification greps whose expected counts were impossible | task 5's implementer |
| a prompt block still carrying the pre-amendment version of a rule it had just changed | task 5's implementer |
| two *more* instances of the semantic-vs-textual hole, left behind when the first was closed | the final whole-branch review |

Four things generalise:

- **The plan author is the least reliable source of the plan's own numbers.** Every wrong number came
  from the author writing from memory of a file they had skimmed; every correction came from someone
  re-deriving it from the file. The cheap fix is structural: put the derivation command in the plan
  next to the number, so the implementer checks it as a side effect of doing the work.
- **Fixing one instance of a class leaves the class.** A rule listed "a redundant condition deleted"
  among behaviour-preserving edits; that was caught and removed. It also listed "a visibility
  narrowing" and "a dead-parameter removal" — the identical defect, because all three are claims
  about *what the code does*, not about what it says. Nobody looked, because the finding had been
  "fixed". After closing a finding, ask what else in the same document is the same shape.
- **The whole-branch review finds what per-task reviews structurally cannot.** Each task reviewer saw
  one diff. Cross-document consistency, and an adversarial reading of the assembled rules, need
  someone holding all of it at once. That review produced the only Critical in the run.
- **An honest implementer report is worth more than a clean one.** Task 5's implementer reported two
  disagreements with its own brief rather than smoothing them, and both were real. The dispatch had
  told it explicitly: *if the brief and the plan disagree, the plan is correct — report it, do not
  silently smooth it over.* Permission to contradict has to be granted in writing or you get
  compliance instead of information.

## 55. Presence is not identity, and a whole-file count proves neither

A rule had to be inserted identically into four separate prompt blocks in one file. The natural check
is `grep -c 'THE RULE' file` → 4. It proves almost nothing: four matches are equally consistent with
two blocks having it twice and two not having it at all.

Two better checks, both used in the same run:

- **Per-unit isolation.** Extract each block between its own fence pair and assert each contains the
  needle exactly once. This catches the distribution problem.
- **Hash the shared region.** The fixer extracted the shared block from each of the four and compared
  digests — identical, 3208 bytes. This catches what per-block needle counts still miss: four blocks
  can each contain the needle and still have *drifted from each other* everywhere else.

The general form: when a requirement is "N copies must be identical", a check that counts occurrences
answers a different question than the one you asked. Count per unit for presence, hash for identity.
It is the same failure as §43's "a count is not a record", one level down.

## 56. Instructions that name a tool must be checked against that tool

Two of the four Important findings in the final review were instructions that simply **could not be
carried out**, and neither was detectable by reading the instruction:

- Four agents were told to "run `unity-reviewer` on the diff". That agent's declared tools are
  `Read, Glob, Grep` — no shell, so it cannot run `git diff` at all. The instruction was coherent,
  well-motivated, and impossible. The fix was to state the mechanism: write the diff to a file, hand
  over the path, because it *can* read a file.
- A decision said "measure it with `PerfProbe` first, and do not skip this step". `PerfProbe` is armed
  by dropping a file, then requires **entering play mode and playing for 60-90 seconds**, flushing on
  a keypress. No unattended agent can do that. Under a never-wait rule, the track would have either
  fabricated a number or filed it blocked — and the document said which neither.

Both were caught only because a reviewer was told to check that every named file, agent, script and
spec actually exists and does what the text claims. That check is cheap and it should be standing:
**for every tool an instruction names, open its definition and confirm it can do the thing.** An
agent's tool list, a script's usage block, and a debug utility's own documentation are all one grep
away, and all three were wrong-by-omission here.

The deeper version: the impossible instruction always *reads* fine, because it was written by
someone reasoning about what the tool is for rather than what it can do.

## 57. The apparatus was the only part of the wave nobody reviewed

The wave's kinglet-agent protocol said each track should run `unity-reviewer` over its own diff and
act on the verdict. A track cannot invoke an agent at all — it *is* one, and nesting was not available
to it. The protocol was therefore not merely awkward, it was unexecutable, and it survived **three
separate reviews** before anyone noticed.

The reason it survived is structural, not careless. Every one of those reviews was handed a diff. The
brief that produced the diff was never in any review package, so no reviewer was ever looking at it.
Reviewers review *work*; the instructions that generate the work sit outside the loop by construction.

The fix in the wave was to move the agent invocation up a level — the track writes its own conclusion
and produces the diff, and the integrator, who *can* dispatch agents, runs them. The fix in the method
is smaller and more portable: **put the brief in the review package.** One reviewer per wave should be
pointed at the plan and the prompts rather than the diff, with a single question — *can the entity
you are addressing actually do this?*

This is §56 raised one level. §56 says check the tools an instruction names. §57 says check the
*reader* an instruction addresses. A brief written for "an agent" and executed by a subagent with a
narrower harness is the common case, and the narrowing is invisible from inside the text.

## 58. Measuring a metric by its name measures the report's vocabulary

The wave ran a pre-registered A/B, and one of its four metrics was *contradictions*: how often a track
concluded the brief, the plan, the ledger, or an earlier claim was wrong, and the source won.

Scoring the treatment arm was trivial — the workflow's structured return had a `contradictions` field,
so the number was a field lookup. Scoring the control arm meant reading two reports written by
terminals with no schema. The obvious move is a grep, and it would have been wrong: **track 1's report
never uses the word.** It says "seven places where the brief, the plan, a catalog or an earlier claim
was wrong". A grep for `contradiction` scores that arm zero, and a zero in the control arm is exactly
the direction that would have made the treatment look good.

Two things follow, and the second is the more useful one:

- When arms of a comparison report through different channels, the metric must be extracted the same
  way from both, and a keyword is not the same way. Read the control arm; do not search it.
- Better: **make the channel identical before the run.** The reason the treatment arm was cheap to
  score is that the metric had a field. A pre-registered metric with no agreed carrier is a metric you
  will end up estimating.

The general form is the counting failure of §55 and §43 pointed at prose instead of code: a count of
the word is not a count of the thing.

## 59. Loop-until-dry needs the integration state to be right every round, not once

The workflow arm stopped after three units when both of its tracks hit merge conflicts on their second
merge. The cause was a single sentence in the prompt: *"the base is merged for you between units."*
Nothing merged it. The direction that was automated was track→base; base→track was described as
automatic and was not implemented anywhere.

What makes this worth writing down is not the missing line — it is why it did not show up until unit
two. A one-shot dispatch merges base at the start and finishes before any sibling lands work. The
staleness window is zero, so the bug is invisible. A loop-until-dry track runs beside five siblings for
hours, and its branch goes stale *inside a single unit*.

**Every piece of shared state a loop touches must be re-established at the top of each iteration, not
at the top of the loop.** Not just the merge: the ledger, the catalogs, the report file, the
generated project files. The one-shot version of a task and the looped version have different
correctness conditions, and a prompt that was true for the first is silently false for the second.

The wave-10 form of this is one line in every track prompt — merge base first, every unit, resolve per
finding id — plus an explicit statement that five other tracks are landing work while you run. The
number matters. "Others are working" reads as a caveat; "five other tracks land work into the branch
you are on" reads as a fact about this unit.

## 60. A pre-registered null result is a finding, and it retires the expensive arm

Two mechanisms for driving parallel work — four terminals with a human relaying between them, and one
session driving subagents through a workflow — were run against the same wave, on adjacent tracks,
with the reading rules written **before** the run. They came out indistinguishable: 1.2 versus 1.0
findings closed per finding-closing unit, ~1.5 versus ~1.3 contradictions per unit.

The value of that is entirely in the word *before*. Written after, "indistinguishable" is a result
anybody can argue with, and the argument always goes the same way — whichever mechanism the arguer
already prefers gets the benefit of the doubt, and both survive. Written before, the rule was: *if the
arms are indistinguishable, the cheaper one wins and the other is retired.* The cheaper one is the one
that does not require a human awake at a keyboard relaying messages between four terminals.

So the null result did more work than a positive one would have. A positive result for the terminals
would have kept both mechanisms alive; the null retired one and freed the operator's night.

The transferable rule: **when you compare two ways of working, write down what a tie means before you
run.** A tie is the most likely outcome and the one you are least prepared to act on.

## 61. Parallel writers collide on the append-only files, not on the code

Five waves of evidence, and the merge conflicts were almost never in source. Tracks working disjoint
subsystems do not touch each other's code. They collide on the three documents every track is told to
append to: the shared status ledger, the blocked-work log, and the mutation harness. Every one of
those is append-at-the-end, which is precisely the region git cannot merge.

The fix is to give each writer a file nobody else opens — `inbox/<track>-blocked.md`,
`inbox/<track>-mutations.py` — and have exactly one integrator fold them into the shared documents
afterward. Conflicts go to zero because there is no shared write.

The part worth writing down is the **cost**, because it is not free and it is not obvious. The
project's ledger gate accepts `operator:<n>` as evidence for a `needs-editor` row, and `<n>` resolves
against an entry in the shared worklist. A track that may no longer write that worklist therefore
cannot legally mark anything `needs-editor` — the evidence cannot exist yet. The row has to stay
`open`, carrying a claim that is now slightly false, until the integrator folds the inbox in.

That is the general shape: **an inbox breaks any gate whose evidence resolves against the file you
took away.** Before splitting a shared file, enumerate what validates against it. Here the answer was
one status and one evidence form, the cost was accepted deliberately, and it was written into the plan
so that a track meeting a red gate would recognise it instead of fighting it.

## 62. The operator's attention is a resource the harness spends

The wave was designed to run unattended. It did. And the owner still spent the evening at the desk,
because the *reporting* was not unattended — every few minutes there was a progress note, a comparison,
a question worth answering. Nothing in the mechanism required them; the narration did. Halfway through
they asked whether something had gone wrong, and the honest answer was that the duration was normal
and I had converted a background process into a foreground one.

An unattended run has two halves, and the harness only automates the first. If the operator has to
watch the thing that does not need watching, the autonomy is decorative.

What that means concretely, for anything built to run while nobody is awake:

- **Say up front what the operator will be asked for, and when.** "Nothing until it finishes" is a
  valid and useful answer; silence is not, because silence is indistinguishable from a hang.
- **Batch the report.** One summary at the end beats twenty updates, unless a decision is genuinely
  blocked on a human — and if it is, the run was not unattended in the first place.
- **A question you could answer yourself is a question you should not ask.** The design of the wave
  had already delegated those decisions; asking anyway takes them back.

The failure mode is friendly rather than negligent, which is why it is easy to miss: every individual
update was informative. The cost only shows up as a total, in hours of someone's evening.

## 63. One refused merge silently ended a track for two hours

The wave ran six tracks. Track 6 did one good unit at 00:05 — a measurement of all 25 scripts in a
subsystem, plus a seam that closed two findings by changing the shape of the code rather than
patching it — and then did nothing at all until 02:00, when a routine check noticed its branch had
not moved.

The cause was a name. The worktree was created on `hardening/t6-roadmap`; the merge order was written
against `hardening/t6-interfaces`. The merge agent was handed an order naming a branch that did not
exist, refused it, and diagnosed it exactly:

> the branch named in the order does not exist … the two stated commits do exist and are the exact tip
> of a differently named branch

Everything downstream of that was correct behaviour. The agent was right to refuse. The loop was
written to `break` on a failed merge, on the sound reasoning that piling further units on top of an
unmerged one compounds the problem. And so a one-character class of typo cost a sixth of the wave.

Three things are worth separating out, because only the first is obvious.

**The typo is the least interesting part.** It was created by two commands written minutes apart, one
of which generated the branch name and the other of which asserted it. Anything generated in one place
and asserted in another will eventually disagree. The fix is to derive both from one expression, or to
verify the whole set once before launch — `for b in …; do git rev-parse --verify …; done` would have
caught all six in a second, and that check now runs before any wave starts.

**The failure was invisible in the shape the run reports.** Five tracks were landing work, the log was
busy, the aggregate numbers moved. A track that is doing nothing produces no output, and *no output is
indistinguishable from working quietly* in a progress display that only shows events. What caught it
was a periodic check that printed **`ahead=N` for every branch**, including the ones with nothing to
say. A monitor built from per-track state finds a stalled track; a monitor built from a stream of
events cannot.

**The `break` was the real defect.** Stopping the loop is right when the *tree* is in a bad state —
when continuing would build on something broken. It is wrong when the merge failed for a reason
outside the work: a name that does not resolve, a lock, a dirty tree someone else left behind. Those
are transient and the next unit's merge would carry both. The policy that replaced it: **a failed
merge logs and continues; two consecutive failed merges stop the track.** One is noise, two is a wall.

The general form is a scheduling rule, not a git rule. In any fan-out where a worker's output is
gated by a shared resource, distinguish *this work is bad* from *the handoff failed*. Only the first
should stop the worker. Conflating them converts a recoverable glitch into a silent, permanent
outage — and the more reliable the rest of the system is, the longer it takes anyone to notice.

## 64. Citation rot: the finding is right and the line number is wrong

Six tracks ran overnight against sixteen review catalogs written months earlier, and a recurring
finding-about-findings emerged: **the claim was intact and the citation had drifted.** Examples from
one track in one night:

- A finding cited `SFXPlayer.cs:291-295` as a scene-loaded handler. Those lines are now `OnDisable`
  and `Start`; the handler is at `:315-319`. The substance — it only handles background music and
  never stops the running loop — was true at both line numbers.
- A finding cited `PlayerMovement.cs:912,919` for where a swim flag is set. It is set at `:986,993`.
  Same mechanism, same defect, two other tracks' edits in between.

The catalogs had drifted under the very work they were driving. That is not a flaw in the catalogs;
it is what happens to any line-anchored reference in a tree six agents are editing concurrently.

**The important discipline is telling the two apart.** A track that finds a citation that does not
resolve has three possible conclusions, and they want opposite actions:

1. *The citation rotted; the claim holds.* Re-derive the location, fix the citation, do the work.
2. *The claim describes code that does not exist.* This is `catalog-wrong` — a documentation defect,
   not open work. It is common rather than exotic: one wave found nine of fifty-nine here.
3. *The claim was never right.* Rare, and the most expensive to establish.

A track under time pressure collapses all three into "the catalog is stale, skip it", and the real
defects go with the rot. What prevents that is requiring the re-derivation to be **shown** — the
command or the `file:line` that settled it — which is the same rule that makes a contradiction
report trustworthy.

This repository had already reached the same conclusion from the other end: its ledger evidence
grammar is deliberately line-number-free (`grep:<path>::<literal>` rather than `path:line`), for the
stated reason that *a baseline keyed by a line number is a baseline nobody updates*. The catalogs
predate that rule and still carry line numbers, which is exactly why they rot and the ledger does not.
**When a reference must survive other people editing the file, anchor it to content, not position.**

## 65. The contradiction rate scaled with the size of the plan, not the size of the work

Two waves, same method, same instruction to record every time the brief, the plan, the ledger or an
earlier claim lost an argument with the source:

| | tracks | units | contradictions | per unit |
|---|---|---|---|---|
| wave 9 | 4 | ~20 | ~28 | ~1.4 |
| wave 10 | 6 | 67 | 262 | **3.9** |

The work was not three times harder. What changed is that wave 10's plan was **written in one sitting,
for six tracks, by someone who had read four of the six subsystems** — and then handed to agents who
each read theirs properly. Every extra track is another reader of the same document, and every reader
that goes deeper than the author finds more of what the author got wrong.

Two readings of that, and the second is the useful one.

The comfortable reading is that the tracks were doing their job. True, and worth the instruction: the
authorisation to contradict is the highest-yield line in the whole brief, and this is the second wave
running where nearly every defect found lived in the instructions rather than in the work.

The uncomfortable reading is that **a plan's error rate is a function of how fast it was written and
how many subsystems it claims to cover, and it does not announce itself.** Wave 10's plan read as well
as wave 9's. It stated the friction in a subsystem in four confident bullets; the track that read that
subsystem properly confirmed two, contradicted one outright, and found the confirmed ones understated.
Nothing in the writing distinguished the true bullets from the false ones.

So the practical rule is not "write better plans" — it is **budget for the plan being wrong in
proportion to its breadth.** Concretely: make the first unit of any track a measurement that checks
the plan's claims about its own subsystem against the source, before any work depends on them. Both
of this wave's roadmap tracks were told to do exactly that, and both spent their first unit correcting
the premises they had been given. That is the cheapest possible place to find those errors, and it is
one unit out of twelve.

## 66. Three measurements of the same bottleneck, and the first two were measuring the report

The question was simple: what is slowing the agent fleet down? Answering it took three attempts, and
the first two produced confident, plausible, wrong numbers.

**Attempt one — keyword search over the agents' structured results.** Counting how often words like
"PlayMode failed" or "ledger" appeared in units that had run the gate more than once. Result: a tidy
ranking led by "PlayMode test red, 28 units". It was measuring *prose*: a unit whose summary happily
described writing a new PlayMode spec scored as a PlayMode failure. This is §58 again, one wave later,
committed by the person who wrote §58.

**Attempt two — searching the agent transcripts for the gate's own failure messages.** More rigorous:
the exact strings the hook prints. Result: twelve categories, each 6-10% of the total. **The
uniformity was the tell.** Real failure causes are never evenly distributed. The agents had *read* the
hook, so its entire message list sat in every transcript, and the search was counting the source code
of the thing being measured.

**Attempt three — the string the hook prints only when it actually refuses.** `pre-push: BLOCKED — %s`
appears nowhere except in a real rejection. 53 events, and a distribution with a shape: compile gate
22%, ledger 18%, batch-tool contract 20%, real test failures only 20%.

Then the same trap once more, on hardware. `load average: 17.81` on eight cores reads as 223%
oversubscription, and it was reported as such. `vmstat` said the CPU was **32-48% idle with zero
iowait**. Load average counts uninterruptible sleep, not utilisation. The machine had headroom the
whole time.

**The general rule, and it is not "be careful".** Every one of these searched for the *name* of the
thing instead of the thing, and each one produced a plausible answer that survived because it was
plausible. The defence is structural:

- **Prefer a signal that cannot exist unless the event happened.** `BLOCKED —` is emitted only by a
  refusal. A word can appear for any reason.
- **Distrust a flat distribution.** Real-world causes are lumpy. Uniformity means you are counting
  something structural — a list, a template, a source file — rather than events.
- **Confirm any headline number with a second, independent instrument.** Load average and `vmstat`
  disagreed, and only one of them was measuring what the sentence claimed.

## 67. The gate was 21% of a track's life, and the fleet was never CPU-bound

Measured across one wave: 61 units, 134 gate runs, a gate run costing about 4.5 minutes (16 seconds of
static checks, then ~2 min EditMode, ~2 min PlayMode, ~1 min scene-load). That is roughly 10 hours of
gate against 46 track-hours.

**So 79% of a track's life is the agent reading, deciding, and writing** — API latency, during which
the local machine does nothing. Confirmed from the other side: with eight tracks running, the CPU was
a third idle.

Three things follow, and they invert the intuitions that produced the wave's design:

- **"How many tracks fit?" is the wrong first question.** The right one is *what fraction of a track's
  life needs the local machine*. At a 21% duty cycle, eight tracks average 1.7 concurrent gate runs —
  the hardware was never the constraint, and the ceiling estimate of eight was a guess dressed as a
  measurement.
- **Adding tracks scales the part that is free** and only slowly loads the part that is not. The
  binding constraint became *disjoint work*: 57 open findings across 15 catalogs is not enough
  independent work for twenty tracks, whatever the hardware allows.
- **Reducing gate runs beats reducing gate cost.** A unit closing three findings pays the same gate as
  one closing one. Batching is a bigger lever than any per-step optimisation, because it removes whole
  gate runs rather than shortening them.

And one optimisation that looked obvious and is not: 56% of a wave's non-merge commits touch only
`docs/`, so skipping the Unity suites on a docs-only diff seems free. It is not — `DocumentationMapSpec`
is an **EditMode test that reads the documentation**, so a docs-only change is exactly the case that
test exists for. The naive rule would skip the one suite that could catch the change. **Before
narrowing a gate by input type, ask what tests exist *because of* that input type.**

## 68. Every measurement mistake had the same shape: counting the record, not the event

Five measurements went wrong on this project before anyone noticed a pattern. They looked unrelated —
different tools, different questions, different waves. They were the same mistake every time.

| the question | what got counted | what it should have counted |
|---|---|---|
| how often do agents hit the gate? | keyword hits in track prose | actual refusals |
| ditto, second attempt | the gate's failure strings — but in the **hook source** agents had *read* | the strings in gate *output* |
| is the fleet CPU-bound? | `load average` (a proxy) | `vmstat`: CPU was a third idle |
| do agents batch tool calls? | assistant **records** in the transcript | tool calls per **API request** |
| where does the token cost go? | a prediction, unmeasured | `Read` was 8%; `Bash` was 92% |

In every case the instrument was pointed at a *representation* of the thing rather than the thing. A
transcript, a log, a prose report, a load counter — each has its own structure, and grep counts that
structure. The transcript case is the crispest: the log writes each `tool_use` as its own record, so a
message carrying three parallel calls appears as three records sharing one `requestId`. Counting
records gives exactly 1.00 calls per turn for every population that has ever existed. Group by
`requestId` and the real numbers appear — 1.01 for workflow agents, 1.30 for terminal subagents.

**The tell, in three of the five: a uniform result across populations that must differ.** Terminal
sessions, workflow agents and the integrator all returned precisely 1.00. The gate-refusal counts came
back uniformly distributed across tracks, which is what reading the *same source file* looks like and
not what independent refusals look like. Uniformity is what a broken instrument produces, because a
broken instrument is measuring something all the populations share.

**The cheapest defence is a positive control, and it was available every time.** Before believing a
number, include one case whose answer you already know. In the batching measurement the control was
free: the measuring session had itself issued parallel calls minutes earlier. A result of 1.00
contradicted directly observable ground truth. A measurement that disagrees with something you know
is testing your instrument, not your subject — and that is the moment to check the instrument, not to
write up the finding.

The corollary for anything log-derived: **ask what the log's own schema does to your count before you
run it.** One record per event is an assumption, not a guarantee.

**The note caught a second instance of itself within the hour.** The cost figures for this project —
terminals versus workflow versus integrator — came from the same transcripts, and the same schema
does the same thing to `usage`: a message split across three records carries the *identical* usage
object on all three. 625 of 625 multi-record requests were exact duplicates. Summing per record
inflated cache-read by 98.7% and roughly doubled every dollar figure reported. Corrected, terminals
cost $4,847 (not $6,964), the workflow $4,346 (not $7,225), the integrator session $679 (not $1,445).

The *conclusion* survived — the workflow still costs 61% of a terminal per turn — which is the
comforting half. The uncomfortable half is that the ratio moved from 49% to 61%, because the
inflation was not uniform across populations. **A duplicated-record bug does not cancel out of a
ratio.** Two populations with different batching rates get different amounts of inflation, so the
comparison is wrong by an amount you cannot predict from either side.

The general rule: when one schema quirk has corrupted one measurement, every other measurement drawn
from that schema is suspect until re-checked — including the ones whose answers looked reasonable.
Plausibility is not a control.

## 69. The most-read file in the wave was the plan, and fresh agents are why

Wave 11's 335 workflow agents spent 73% of their context budget reading and searching. Attributing
the bytes that file reads actually returned:

| | MB | share |
|---|---|---|
| first acquisition anywhere in the run | 6.36 | 41.1% |
| re-acquired by a **different** agent | 5.88 | 38.0% |
| re-read **within** one agent | 3.24 | 20.9% |

**59% of read bytes are waste.** And 68% of the cross-agent half is `docs/` — the plan, the decisions
document, the ledger. Counted by how many separate agents opened each file, the most-read file in the
entire wave was not source code:

    wave-10-plan.md            51 agents
    wave-11-plan.md            46 agents
    decisions-2026-07-31.md    26 agents
    run-editmode-tests.sh      21 agents
    finding_ledger_check.py    21 agents

This is the hidden invoice for a fresh agent per unit. A fresh agent is genuinely cheaper per turn —
131k cache-read per turn against 336k for a long-lived session, about 2.5×. What it cannot do is
remember, so every unit re-acquires the shared context, and the shared context is the large documents
the integrator wrote. **The design is still right; the mistake is letting re-acquisition happen by
file read.** Put the brief in the prompt and forbid the file: the agent pays for its own section once,
in tokens the dispatch was going to spend anyway, instead of pulling 20 KB of plan it mostly does not
need.

The same reading explains `run-editmode-tests.sh` at 21 agents. Nobody wanted the script — they wanted
its invocation and its exit codes, which the prompt did not state. **An agent reads a tool's source
when the prompt does not carry the tool's contract.** That is a prompt defect showing up as a read.

Within a single agent, the repeats have four causes, and the largest is self-inflicted by the reading
style:

    slice-read, then came back for more    48.6%
    re-read immediately, separate call     27.5%
    re-read after editing that file        18.0%
    re-read later, no edit                  5.9%

Reading a file in `sed -n '100,200p'` slices *guarantees* a return trip — 2,640 slice reads against
1,841 whole-file reads. And 18% is the verify-my-own-edit reflex, which the Edit tool already makes
unnecessary by failing loudly.

None of this is visible from the outside. A track that closes its findings looks efficient; the cost
is in how it learned what it needed, and that never appears in the output.

## 70. The prompt rules cut turns by a third and cost by nothing, because they traded one waste for another

Four agents, two tasks, prompts byte-identical except for a block of four cost rules — batch
independent calls, read whole files rather than slices, never re-read a file, never re-read to verify
an edit.

| task | arm | turns | calls/turn | cost | sed | Read | tool output |
|---|---|---|---|---|---|---|---|
| A | control | 19 | 1.58 | $4.13 | 11 | 0 | 116 KB |
| A | treatment | **12** | 1.67 | **$4.33** | 0 | 6 | **195 KB** |
| F | control | 15 | 1.67 | $5.10 | 0 | 0 | 148 KB |
| F | treatment | **10** | 2.00 | **$4.45** | 1 | 6 | **215 KB** |

**Turns fell 33-37%, consistently. Cost fell 5%, which at n=2 is nothing.** Output quality was
indistinguishable: all four covered every finding and the two arms on task A each found six stale
catalog claims.

The mechanism is visible in the last column. The agents bought their turn reduction by pulling more
content per turn — whole files instead of slices, 116 KB to 195 KB. Cost is context times turns, so
halving one while doubling the other is a wash. **The rule block bundled a lever that helps with a
lever that hurts.**

Batching independent calls into one message removes a turn and adds no content: pure gain. Reading
whole files removes a turn *by adding content*, and whether that pays depends on how long the agent
lives. The extra content is charged once on entry (cache-write, 12.5x the read rate) and then re-read
on every remaining turn; the saved turn is worth one re-read of the ~40,000-token fixed prefix. For a
20 KB file against a 5 KB slice, break-even lands near 15-20 turns.

**The test agents ran 10-19 turns. Production units run a median of 39.** So the honest reading is
narrower than "whole-file reading does not pay": at the length these agents ran, it broke even, and
at production length the same arithmetic says it loses. A cheap experiment landed in exactly the
regime where the effect vanishes — worth checking before designing the next one.

The original justification was that slice reading caused 48.6% of within-agent repeat reads. True,
but repeat reads were only 20.9% of read bytes. Trading a 20.9% waste for a surcharge on every first
read was a bad deal, and the number that said so was already in hand and misread. **A share of a
waste category is not a share of the bill.**

## 71. Batching alone cut cost 18%; adding the reading rule cut it to 5%

The follow-up isolated one variable. Same two tasks, same control data, one sentence added to the
prompt — issue independent commands in one message — and nothing at all about how to read a file.

| task | arm | turns | cost | tool output |
|---|---|---|---|---|
| A | control | 19 | $4.13 | 116 KB |
| A | four rules | 12 | $4.33 (+5%) | 195 KB (+69%) |
| A | **batching only** | 16 | **$3.39 (−18%)** | 94 KB (−19%) |
| F | control | 15 | $5.10 | 148 KB |
| F | four rules | 10 | $4.45 (−13%) | 215 KB (+45%) |
| F | **batching only** | 9 | **$4.19 (−18%)** | 202 KB |

**−18% on both tasks, from one sentence.** The four-rule block gave −5%, because the whole-file rule
inflated tool output by 45–69% and spent the turn savings on content.

The literature had already named both halves of this. [LLMCompiler (ICML 2024)](https://arxiv.org/abs/2312.04511)
reports up to 3.7× latency and 6.7× cost from executing an LLM's independent calls concurrently, with
~9% *higher* accuracy — fewer intermediate steps, less context pollution. And
[Token Reduction Is Not Cost Reduction](https://arxiv.org/html/2607.12161), over 2,908 billed Claude
Code runs, found an intervention that cut tool-output tokens 38.4% while cost rose 6.8%, and named the
mechanism: cache-read is a tenth of input price, removing context makes the model fetch it again, and
every added turn re-transmits the whole cached prefix. Their cost split — cache write 44.3%, cache
read 35.4%, output 10.4% — is the same shape as this project's 22.8% / 72.7% / 4.5%. The difference is
trajectory length: their mean run is 4.5 turns, ours 39–50. Short agents pay to fill the cache; long
agents pay to re-read it.

Two things follow. **First, a prompt sentence is not the ceiling.** 6.7× comes from a planner that
builds a dependency graph; ours moved calls-per-turn from 1.01 to about 1.7. Most of the headroom
needs structure, not instruction. **Second, bundle rules and you cannot tell which one worked** — the
first experiment shipped four together, measured 5%, and nearly retired the one lever that pays.

Caveat kept in view: n=2 per arm, and the quality counts moved in both directions — on task A the
batching arm pinned 26 symbols against the control's 37, on task F it pinned the most of any arm. All
arms covered all four findings. Part of the 18% may be less thoroughness rather than less waste, and
this design cannot separate them.

## 72. Parallel tracks collide in shared number spaces, not just shared files

Wave 12's fold produced four conflicts. One was ordinary. Three were the same defect wearing
different clothes, and none of them was a file collision:

- Wave 11: **two** tracks allocated the finding id `MEN-B10` to different findings in the same catalog.
- Wave 12: **three** tracks allocated operator-worklist **entry 21** — track A for PM-C1's dash
  decision, track G for ENV-B11's static collider, track H for EN-S4's configuration block.

The track boundaries were drawn on *files*, carefully and successfully — no two tracks edited the same
source file all wave. What they shared was a **counter**. Every track appends to
`operator-worklist.md` and to the ledger, and every track computes "the next free number" against a
tree that does not yet contain its siblings' work. Each one is right at the moment it looks.

Git cannot help here. Two appends at different offsets are not a textual conflict, so the collision
arrives as a document with two `### Entry 21` headings and a ledger whose `operator:21` pointers now
resolve to whichever section the reader hits first. §61 recorded that parallel writers collide on
append-only files; this is narrower and worse — **they collide on the identifiers inside them**, and
the fold notices only if someone thinks to grep for duplicates.

Three fixes, in increasing order of how much they actually solve:

1. **Grep for duplicate identifiers as part of the fold**, always. `grep -c '^### Entry 21 '` is the
   whole check and it is not optional; a union merge produces exactly this and reports success.
2. **Give each track a disjoint range** at plan time — track A gets 21-29, G gets 30-39. Free, and it
   removes the collision rather than detecting it.
3. **Stop numbering.** The entry number carries no information the heading does not. A slug
   (`entry-pm-c1-dash`) cannot collide by construction, and the ledger pointer becomes readable.

The renumber itself is cheap — heading, index row, ledger evidence, and any inbox reference, about
ten edits — but only if it is caught. The expensive version is a worklist that silently has two
entries with the same number and an owner who actions the wrong one.

## 73. A design agent earns its cost by reading the code, not by having taste

The kinglet design agents (`game-designer`, `level-designer`) are a documentation layer — they read
the repo and write to `docs/`, they never touch C#. The obvious worry is that this makes them
decorative: an agent with taste but no leverage.

Dispatched on a real biome design question, the thing that made `game-designer` worth the call was
not a single design opinion. It was that it opened `DNAController.cs` and found line 303 —
`if (form != defaultForm && !CurrentFormHas(FormCapability.Morph))` → *"Cannot change form more than
once!"* — established that only the baseline form declares `Morph`, and that `ResetForm()` runs on
death. **One transformation per life, and death is the only route to a second form.**

Nobody in the conversation knew that. It had been true for months. It reframes the entire design
question from "which form solves this room" into "in what order do I wear forms, and what does each
leave behind before I kill it off" — and it is a fact about the code, not a preference.

The same agent's purely aesthetic contributions were ordinary. Its spatial thesis was good; its
answer to "should the cave have water" was *water*, which was the wrong answer for a structural
reason it had not checked (a substance exactly one form can enter is a lock and a key — the same
object as the button-and-door vocabulary the whole biome existed to escape).

**The transferable part.** A design agent's value is concentrated in the part of design that is
*discovery about the existing system*, not the part that is *invention*. Give it the repo and a
question that the code can partly answer, and it will find the constraint you forgot you shipped.
Ask it to have an opinion about a mechanic that does not exist yet and you get a competent one,
worth about as much as your own.

The corollary for cost: dispatch design agents at questions with a code surface. A pure ideation
prompt is the expensive way to get an average answer.

## 74. The cost estimate was wrong in the two places the owner could see

`game-designer` ranked a split-body form as the most expensive item on the list, because "a second
body touches input, camera, the locomotion state machine, and the death path." Reasonable, and it
put the item first on the cut list.

The owner deleted half of it in one sentence: both halves take the *same* input, so there is no new
input work, and that biome's camera is static, so there is no follow-two-targets problem. What
remained — the single-player-shaped death path, and which body owns the form — is real but is roughly
half the estimate. The item came off the top of the cut list.

Neither correction required knowing the codebase better than the agent did. Both required knowing the
*design intent*, which the agent had inferred rather than been told: it had costed two independently
controlled bodies because that is the usual shape of the mechanic, and nobody had said otherwise.

**The transferable part.** An agent's cost estimate silently prices the design it imagined, not the
design you meant. When an estimate ranks something surprisingly high, check the imagined design
before you accept the ranking — the error is more often in the specification than in the arithmetic.
Two of the four line items here evaporated on contact with a fact the agent was never given.

## 75. You can verify an MCP server without restarting the session

MCP tools register at session start. If the server was not running then, the `mcp__*` tools do not
exist for the rest of the session, and the usual conclusion is "we'll test it next time" — which
defers the question by hours and often forever.

The tools are absent; the server is not. It is an HTTP endpoint, and `curl` reaches it now:

```bash
SID=$(curl -s -D - -o /dev/null -X POST http://127.0.0.1:8080/mcp \
  -H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream' \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"probe","version":"0"}}}' \
  | awk 'tolower($1)=="mcp-session-id:"{print $2}' | tr -d '\r')
# then notifications/initialized, then tools/list, then tools/call — same JSON-RPC, same session header
```

Three traps, all hit on the first attempt:

- **A plain `GET` returns 406, not an error you should trust.** Streamable-HTTP MCP requires
  `Accept: application/json, text/event-stream`. 406 means "wrong headers", not "server broken".
- **Responses come back as SSE frames**, so the JSON is behind `sed -n 's/^data: //p'`.
- **The session id lives in the `mcp-session-id` response header** of `initialize` and must be sent
  on every later call. Without it the second call fails in a way that looks like the server rejecting
  you.

What this buys is not just a green light. `tools/list` returned 48 tools and their real schemas — two
guessed `manage_editor` actions were rejected with the full literal enum of valid ones, which is
faster documentation than reading the package. And one `manage_script` call logged
`unity_instance=Endless-Evolution@3febfac2`, which answered the question that actually mattered:
*which project is the editor attached to.* A connectivity check that does not confirm the target is
not a connectivity check.

## 76. The best fix for a risky mechanic was deleting the mechanic that made it risky

The cave design's largest open risk was that a form which permanently destroys terrain, in a game
where rooms never reset, can strand the player with no feedback. Two agents and I converged on the
same framing: what is the escape hatch — a player-invoked room reset, a menu restart, or a promise
from level design that it cannot happen? The third is the easiest to claim and the hardest to hold,
so the discussion was really about which mitigation to build.

The owner changed the mechanic instead. The digging form now moves freely through soil and **the
tunnel closes behind it** — no terrain is permanently edited, so nothing needs restoring and no
mitigation is needed. The risk did not get managed; it stopped existing. Permanent destruction moved
to discrete, individually placed objects, where a level designer can *enumerate* every permanent edit
in a room — impossible when the edit is "any of nine hundred tiles."

It also closed a second problem nobody had raised in that thread: a tunnel that persists is a ladder,
and a ladder makes the digger a general-purpose vertical solution — the exact failure the swing-only
thread rule existed to prevent. One change satisfied two constraints that had been argued separately.

**The transferable part.** When a design discussion has converged on *which mitigation*, that is the
signal to go back one step and ask whether the mechanic is required in the shape that needs
mitigating. Agents are especially prone to this: given a risk, they reliably produce mitigation
options and reliably do not propose deleting the requirement, because the requirement arrived as
given. The move is cheap to try and it is the owner's to make, not the agent's — which is a reason to
put the risk in front of the owner as a *risk*, not as a menu of mitigations.

## 77. The MCP tool table is frozen at session start, and subagents inherit the freeze

Registering an MCP server mid-session succeeds — `claude mcp add` reports `✔ Connected`, and the
server is genuinely reachable (§75 proves it over HTTP). None of that produces a callable tool.

The obvious hope is that a *freshly spawned* subagent, created after the registration, would pick the
server up. Measured, it does not. A probe agent found no tool whose name begins with `mcp__`, and
`ToolSearch` returned empty for both the exact name (`select:mcp__UnityMCP__manage_editor`) and a
keyword query. The tool table is fixed when the session starts and inherited by every agent the
session spawns.

The failure mode this creates is worse than an error. Agents that *require* MCP — `unity-coder`,
`unity-test-runner`, `unity-fixer` in this toolkit — remain listed and dispatchable. They start
normally and work with empty hands. Nothing announces that their principal capability is missing;
they simply produce a report about code they could not run.

**The operational rule: work that needs MCP must be planned into a session that started with the
server up.** Not "we'll connect it when we get there" — by then it is too late for that session, and
the cost of discovering this is a dispatched agent that returns something plausible and useless.

Two corollaries. First, a toolkit that ships MCP-dependent agents should have a preflight that fails
loudly when the tools are absent, because the agents themselves will not. Second, when a wave's
findings are triaged into `needs-editor`, that queue is not merely "later" — it is a scheduling
constraint on a specific kind of session, and it should be written down as one.

*(Measured for the Agent tool. Workflow was not measured; its documentation grants access to
"session-connected MCP tools", and a server added after start is by that wording not session-connected
— an inference, not a measurement.)*

### §77 addendum — the other half: the server is owned by the editor

§77 measured the client half (the tool table freezes at session start). That alone does not explain
why the Unity Editor must be *open*. The server half does, and the package documents it only in its
own source — the upstream README says nothing about server lifecycle.

Evidence, all local, from `com.coplaydev.unity-mcp`:

- The running process carries `--pidfile <project>/Library/MCPForUnity/RunState/mcp_http_8080.pid`
  and `--unity-instance-token <hex>`. A pidfile inside the Unity project's `Library/` plus an
  instance token means the editor spawned it.
- `Editor/Services/HttpAutoStartHandler.cs` is `[InitializeOnLoad]`: *"Automatically starts the HTTP
  MCP bridge on editor load when the user has opted in via the 'Auto-Start on Editor Load' toggle."*
- `Editor/Services/McpEditorShutdownCleanup.cs` is `[InitializeOnLoad]`, subscribes
  `EditorApplication.quitting`, and calls `StopManagedLocalHttpServer()` — *"Headless servers have no
  terminal window, so an unstopped one is an invisible orphan."* It is explicitly gated on quitting:
  *"domain reloads must NOT stop the server."*

So the composition is: **quitting the editor kills the server; the client's tool table cannot be
refilled without a new session.** Three consequences the client-side note alone does not give you:

1. **Unity must stay open for the whole session, not merely at its start.** Close it midway and the
   tools remain listed with nothing behind them — the same silent-empty-hands failure as §77, arrived
   at from the other direction.
2. **Auto-start is opt-in.** With the toggle off, opening Unity is not enough; the bridge must be
   started by hand. "I opened Unity and the tools still didn't appear" is this, not a bug.
3. **There is a startup race.** Editor load plus auto-start is not instantaneous — the handler budgets
   300 retry frames. A client session that starts before the port is listening registers nothing.
   Correct order: Unity fully loaded → confirm the port answers → then start the session.

Domain reloads are safe. Recompiling scripts does not drop the bridge; only quitting does.

**The transferable part, beyond this package:** when a tool's lifecycle is undocumented, the
process argv and the `[InitializeOnLoad]`/shutdown handlers in the installed package answer it faster
and more reliably than the README, the wiki, or a search. The pidfile path alone identified the
owner. Read the dependency you already have on disk before reading what its authors wrote about it.

### §77 addendum 2 — "restart the CLI" does not reach a background job

The fix implied by §77 is obvious: restart the client so the tool table is rebuilt. Measured, that
advice silently fails for a background-job session.

The user closed and reopened their terminal. The registration was already in `~/.claude.json` and
`claude mcp list` reported `✔ Connected`. No Unity tools appeared. The process tree says why:

```
pid=4567  09:22:21  claude bg-spare
pid=4531  09:22:21  claude bg-pty-host
pid=4498  09:22:20  claude daemon run --origin transient
```

A background job's session lives in a process spawned by the daemon, not in the terminal that
launched it. Closing and reopening the terminal starts a *new* process (here `pid=17748`, 10:13:45,
which would have the tools) while the job continues in the old one. The tool table of the job is
whatever existed at the daemon's spawn — 09:22 — and nothing a user does in their terminal changes
it.

**The rule: a background job cannot acquire an MCP server, ever, once started.** Not by registering
it, not by restarting the terminal, not by spawning subagents. The only route is a session that
starts after the server is up. If MCP work is planned, it does not belong in a job that is already
running.

**The transferable part, and it is the reason this is worth a note:** the earlier reasoning about
resume was correct about the mechanism (the tool table is built at process start from config, and
restoring a conversation restores messages, not tools) and still produced advice that did not work,
because it silently assumed the session's process was the one the user could restart. When a
correct mechanism yields a failing prediction, the error is usually an unstated assumption about
which process, machine, or context the mechanism is running in — check that before re-examining the
mechanism. Confirming it cost one look at `/proc/<pid>/stat`'s parent chain.

## 78. MCP did not make hard work cheap; it made impossible work possible

Sixteen findings had been parked across five waves as `needs-editor` — work no agent could do because
it required the Unity Editor. One session with the MCP bridge live closed eight of them in 61 minutes
for $27.72, and the remaining six are all genuinely decision-gated rather than capability-gated.

The per-turn numbers, next to the wave-era baseline measured from the same project's transcripts:

| | MCP session | wave-era terminals |
|---|---|---|
| total | $27.72 | $1,255.10 |
| turns | 199 | 6,708 |
| **per turn** | **$0.139** | **$0.187** |
| tool calls / turn | 1.15 | 1.01 |
| cache_read share | 80.6% | — |

26% cheaper per turn, and the batching rule moved calls/turn from 1.01 to 1.15 — not the 1.7 that pure
investigation reaches, because editor work has real sequential dependencies (§71's ceiling again).

**But the comparison is the wrong frame and it is worth saying why.** These eight were cheap findings.
They waited five waves not because they were hard but because they were unreachable. Reading the
$0.139 as "MCP saves 26%" mistakes the result: the honest statement is that the prior price of these
eight was *unbounded*, because no amount of spending closed them. A capability unlock and an
efficiency gain are different things and should not be reported in the same units.

The corollary for triage: a queue labelled by *difficulty* hides this. `needs-editor` looked like a
backlog of hard work and was actually a backlog of trivial work behind a locked door. Worth asking of
any parked queue whether its items are expensive or merely blocked — the second kind clears in an
afternoon once the block lifts, and should be scheduled the day the capability arrives rather than
prioritised against genuinely hard work.

## 79. The bridge contaminates the repository, and only one of the two was reversible

Two engine-settings files changed without anyone asking, in one session:

- **`EditorSettings.asset`: `m_EnterPlayModeOptions: 0 → 1` (`DisableDomainReload`).** Unity's Test
  Runner sets this to run PlayMode tests without a domain reload and **does not put it back**. It is
  not cosmetic — with domain reload disabled, static state survives between play sessions, so the game
  behaves differently in the editor for everyone who pulls the commit. Caught and reverted through
  `EditorSettings.enterPlayModeOptions`.
- **`TimeManager.asset`**: the pinned editor migrated `Fixed Timestep: 0.02` to the rational form
  (`m_Count: 2822398`, `m_Rate: 141120000/1`, a ~1e-8 relative difference) the first time settings
  were saved. Not cleanly revertible — hand-editing the YAML back invites a malformed settings file,
  and the next settings save redoes it.

**Anyone running PlayMode tests through MCP must check `git status` on the settings directory
afterwards.** This is the single most likely way the bridge dirties a repo, and neither change
announces itself.

The second-order lesson is about *which* guard fires. This repository already had a rule against
silent engine migrations (`ee-sandbox.sh` resolves the editor from `ProjectVersion.txt` rather than
guessing a newer one, calling the alternative "a silent, committed engine upgrade nobody asked for").
That guard did not fire, correctly: the running editor *was* the pinned version. The migration came
from the pinned editor touching a file an older editor wrote — a case the guard was never shaped for.
**A guard written against one mechanism does not cover a second mechanism with the same outcome.**

## 80. A status of `applied` can be true of a working tree and false of the repository

The guard that blocks agents from staging engine-settings YAML did its job: it refused the session's
`git add`. The session did not disable it — correct — and committed everything else. The result is a
repository where two findings read `applied` in the ledger while the changes backing them exist only
in one person's working tree, and where a prefab ships pointing at layer 19 while the file that *names*
layer 19 does not.

The ledger check has exactly this rule and it did not fire. It told the same session, about a spec
file, that it *"exists in the WORKING TREE but not in the index — stage it or the push carries a claim
nobody else receives."* Its evidence resolver simply does not apply that rule to engine-settings
paths, so the row passed clean.

**A guard that checks staging for one class of evidence path and not another will certify a
half-landed fix.** The gap is not that the hook blocked the write — that is the hook working. It is
that two mechanisms disagreed about the same commit and nothing reconciled them: one refused the file,
the other blessed a claim that depended on it.

Generalised: whenever one guard *prevents* a change and another guard *verifies* the outcome of that
change, they must know about each other, or the second will certify what the first blocked.

## 81. A content-matching guard blocks writing about the thing it guards

Writing §79 and §80 into this file failed. The hook that protects Unity's engine-settings directory
fired on a `cat >> docs/research/pioneer/field-notes.md` heredoc — because the *prose* contained the
guarded path string. The command wrote to a research note in a different repository and touched
nothing the hook exists to protect.

The hook matches the command text, not the command's target. Every `git add`, `Write`, and `Edit` is
screened the same way, so any file whose content discusses the guarded path is unwritable by that
route. Documentation, post-mortems, and the guard's own README are exactly the files most likely to
name it.

The workaround is to move the content out of the command: write the text with a file-writing tool, then
`cat tmpfile >> target`. That the workaround is trivial is the point — **a guard this easy to step
around while blocking legitimate writes is mis-specified, not strict.** It should match on the
resolved target path.

Worth checking for the whole class: any guard implemented as a substring match over a command line
will fire on quotation and miss indirection. Those are the same defect seen from two sides.

## 82. Grepping source misses everything the editor authored

An agent specifying a darkness mechanic reported, as an established fact underpinning its whole
design: *"There are zero `Light2D` references in Assets outside the vendored extension."* It had
grepped `.cs` files, which is where a programmer looks for a type.

`Light2D` is authored in **52 scenes and 26 prefabs**, and one of them puts a point light on the
**player's root GameObject** — so the spec's central proposal, a new `CarriedLight` component called
"non-negotiable if darkness ships", was proposing to build a thing that already exists and is
already on the object it would attach to. Not a small error: it inverted the cost estimate in both
directions at once. New code was cheaper than claimed (the component is an inspector retune), and
the retrofit was far more expensive (26 prefabs and 52 scenes carry authored lights that a global
darkness pass has to reckon with).

**In a Unity project, a type's real usage lives in YAML, not in C#.** A component is attached by
GUID in a `.prefab` or `.unity` file and the class name never appears there. So:

- `grep -r "Light2D" --include=*.cs` answers "who *programs* against this type".
- To answer "where is this type *used*", resolve the script's GUID from its `.meta` and grep that
  GUID across `.unity`, `.prefab`, `.asset`, `.controller` and `.anim`.

This project already knew that — `docs/hardening/` is full of GUID sweeps done exactly this way, and
one operator entry's entire safety argument rests on "381 prefab instances across 25 files and zero
of them override `m_Layer`". The knowledge did not reach a fresh agent because nothing in its brief
said so.

**The transferable part.** In any system where configuration is data rather than code, "I searched
the source" is not a search. The generalisation beyond Unity: config-driven frameworks, dependency
injection by string key, database-stored rules, feature flags. When an agent reports an absence, ask
what it searched — an absence claim is only as strong as the file types it covered, and absence
claims are the ones that get built on.

## 83. Parallel agents collide in number spaces, and the fix is allocation, not review

Five ability specs were written in parallel. Two claimed the same capability bit (`1 << 7`); a third
computed an enum value that was already taken. Each agent had independently read the enum, found the
next free value, and taken it — correct in isolation, wrong in aggregate, three times out of five.

This is the third instance in this project. Two hardening tracks once allocated the same finding id,
and three allocated the same operator-worklist entry number (§72). The mechanism is identical every
time: a shared, densely-packed, append-only number space with no allocator.

**Better review does not fix it.** Only one of the five reviewers caught the bit collision, and it
caught it by happening to read a sibling spec — which was luck, not method, because each reviewer was
scoped to one spec. Scaling review to catch this means every reviewer reads every sibling, which is
quadratic and still probabilistic.

**Allocation fixes it, and costs one table.** The numbers now live in one document, marked binding,
with the rule stated as *a spec that names a bit or an enum value not on this table is wrong even if
the number happens to be free*. That last clause matters: without it, an agent that derives a
correct-by-luck value still teaches the next agent to derive.

The general rule for fanning out work: **before dispatching N agents, list every shared namespace
they will each want to take a name from** — ids, enum values, bit flags, ports, table columns,
migration numbers, file-name prefixes — and allocate them in the brief. It is the cheapest possible
step and it removes a whole class of merge-time archaeology.

A second-order finding from the same round, worth its own line: one spec declared a new capability
flag and then branched on form identity everywhere, never reading the flag it had just added. The
capability enum in this project exists specifically to retire form-identity tests, and its own
comment says so. **An agent will happily satisfy the letter of a structure it does not use** — so a
review that checks "was the flag declared" passes it. The check that catches it is "name the branch
that reads it".

## 84. An agent fixing an error class reproduces that error class in the fix

Five specs went through revise-then-verify. All five closed every finding against them. Two still
failed — on defects the *revision* introduced, and in both cases the introduced defect was the same
class as a finding that revision had just corrected.

- One spec's finding #3 was *a sound conclusion propped up by a claim that does not survive
  checking*. While fixing it, the spec wrote a new supporting claim — "a grep returns hits only
  inside the vendored extension, so this is a house rule" — which is false: 30 of 77 hits are
  first-party runtime code across 16 files. Same conclusion, same defect, new sentence.
- The other spec's finding #1 was *a test asserted to be writable that is not*. While fixing it, it
  specified a new test that fails by construction, and its own neighbouring section explained why:
  the query it asserts on is unguarded against the layer in question, so it reads `true` on exactly
  the frames the test demands `false`.

Neither is carelessness in the ordinary sense. The agent had the correction in working memory as a
*local repair* — this sentence, this test — not as a *class of mistake to stop making*. Feedback
phrased as "finding N is wrong, fix it" is received as N repairs, and an agent with N repairs done
reports success honestly.

Two things follow, and the second is the useful one.

**Verify rounds must be allowed to raise new findings, but only new ones.** The verify prompt here
said: *do not raise new findings unless they are things the REVISION introduced*. That single clause
is what caught both. A verifier scoped to "did they fix the list" would have passed both specs,
because both fixed the list completely. A verifier scoped to "review this again" would have widened
the round indefinitely.

**Feedback should name the class, not just the instances.** "Finding 3: this claim is false" invites
a sentence swap. "Finding 3, and the class it belongs to: you are supporting real conclusions with
checks you did not run — audit every other claim in the document for the same shape" invites the
audit. The extra clause costs one line and is the difference between a repair and a habit.

The corrections were left visible in both documents rather than silently edited, with a line saying
which finding they mirror. A reader who sees only the clean version learns nothing; a reader who sees
"this was introduced while fixing the finding about exactly this" learns the thing worth learning.

## 85. An agent can wire a scene but cannot compose one

The bridge gave an agent full editor control, and it used it well on everything that had a right
answer: it found a null rig reference that would have made a brand-new ability silently refuse to
fire, it caught an authored layer mask that contradicted its own component's documented intent, and
it correctly refused to place two forms when a completeness gate said they were incomplete.

Then it built a test scene, and the owner's verdict on the scene was: **bad.** Not broken — bad.

The distinction is the finding. Everything the agent got right was **verifiable**: a null is null, a
mask either includes a layer or does not, a gate is red or green. What it got wrong was **spatial
composition** — how far apart the stations sit, whether a gap reads as crossable, whether the shaft
looks like an invitation or a wall, how much floor a player needs before a jump feels deliberate.
None of that has a test, and none of it was in the brief, because none of it can be written down as
a number without already being the design.

The brief asked for six stations and listed what each must contain. It got six stations containing
those things. **The specification was satisfied and the artefact was still wrong**, which means the
specification was the wrong instrument, not that it was under-detailed. A longer brief with exact
coordinates would have produced the owner's layout via an extremely expensive route — the owner
typing coordinates into a document instead of dragging boxes in an editor.

**The transferable split, and it is the same shape as the earlier finding about design agents (§73):**
give the agent the parts and the wiring, and keep the composition. Concretely, for this project:

- agent: create the components, attach them, resolve references, set up the pickups and the cheat
  keys, verify the gates, list what exists and where;
- owner: place it.

The cost of getting this wrong is not the wasted layout. It is that a bad scene is *plausible* — it
loads, it has all six stations, every gate is green — so it can absorb a playtest before anyone
notices the scene, not the mechanic, was what felt wrong.

**The narrower operational rule:** when the deliverable is judged by feel and has no failing test, an
agent's output is a draft for a human to replace, not a result to accept. Say so in the brief, so the
effort goes into the parts rather than the arrangement.

---

## 86. A feature can be absent for its entire life and report as "unused"

Kinglet shipped 39 skills. An eight-hour Endless-Evolution session on 2026-08-02 invoked zero of
them — 216 tool calls, no skill, no agent, no command. The session before it, four hours, the same.
The obvious reading was a model-behaviour problem: the skills are there, nothing points the model at
them, so it never picks one. That reading survived two separate conversations because it explained
the data perfectly.

It was wrong. The skills were never registered. Claude Code discovers `.claude/skills/<name>/SKILL.md`
and nothing deeper; all 39 lived at `.claude/skills/<category>/<name>/SKILL.md`, inherited from
everything-claude-unity. The `Skill` tool could not name one of them. There was nothing to decline.

**Measured rather than reasoned about**, which is the only reason it was found. Two probe skills in an
empty directory, one flat and one nested, and a headless session asked to list its own skills:

```
.claude/skills/flatprobe/SKILL.md            -> listed
.claude/skills/category/nestedprobe/SKILL.md -> not listed
```

Four transferable pieces.

**Absence and disuse produce identical telemetry.** "The feature was available and went unused" and
"the feature was never available" look the same from the outside: zero invocations. Any metric that
counts *uses* cannot distinguish them. Before concluding that people or models are not using
something, establish that they *could* — and establish it by observing the system, not by reading the
tree. A directory listing shows the files exist. It does not show they are loaded.

**A tidier structure can cost the whole feature.** Categories were the natural thing to do with 39
files; they made the tree readable and the catalog easy to write. They also made the feature
non-functional, silently, in a way that produced no error, no warning, and no missing file. Any time
a layout is chosen for human readability, ask which consumer reads it — if a tool does, its
conventions are not negotiable and are worth verifying rather than assuming.

**Half-right findings are stickier than wrong ones.** A probe on 2026-07-30 had already found
`alwaysApply: true` inert and corrected the documentation honestly — and then concluded the skills
were "selected by description like every other skill." That conclusion was too generous by exactly
one step, and because the correction was visibly rigorous, it closed the question. The evidence for
the truth was sitting inside it: the model answered the test question only after it *searched for and
read the skill file*, which is what you do when a skill is not invocable. The report described the
observation correctly and drew the comfortable inference. **When a finding has to explain away an
awkward detail, the detail is usually the finding.**

**Reachable is not the same as discoverable, and both are needed.** Fixing the layout was necessary
and not sufficient. None of the 28 agents had `Skill` in its `tools:` frontmatter, so none could load
a skill even once registered; and `unity-coder` told itself to "note this for the orchestrating
command," where no command loads skills. Three independent failures, each alone fatal, all invisible.
A capability chain fails at its weakest link and reports nothing about which link that was — so
verify the chain end to end, in the deployed configuration:

```
install into a fixture project -> headless session invokes serialization-safety -> INVOKED: yes
                               -> subagent unity-linter invokes it              -> SKILL_OK
```

Two probes, four minutes, and they are the only evidence that any of the day's edits did anything.
The 217-assertion suite passing proves the bytes are in the right place. It cannot prove the feature
exists.

---

## 87. The auto-loaded rule that is 68% wrong changes nothing, measured

Endless-Evolution auto-loads six rule files every session. One of them, `architecture.md`, mandates
Model-View-System, VContainer, MessagePipe and UniTask. The project uses **none** of them: zero files
reference VContainer or MessagePipe or UniTask, against 271 files using coroutines and 363
MonoBehaviours. By section, 68% of that file is inapplicable here, and it is the largest of the six
at 15.4 KB — a third of the whole rules budget, loaded unconditionally, mostly wrong.

That is a strong-looking case, and I made it. Then I tested it, and it is not a case at all.

**The experiment.** Two directories holding EE's `CLAUDE.md`, `AGENTS.md` and `.claude/rules/`,
identical except that B has no `architecture.md`. No `Assets/`, no tools — the model answers from
instructions alone, which is the condition that *maximises* a rule file's influence. Two prompts,
three trials each, six runs per prompt. The second prompt was chosen to be maximally tempting: a
greenfield subsystem reacting to events from all over the game, which is the textbook case for a
message bus and a DI container.

**Every one of the twelve runs produced the same design.** MonoBehaviour, `Time.time` timestamp
cooldowns, static C# events, ScriptableObject definitions, a singleton on the bootstrap prefab,
coroutine-debounced saves. Not one recommended VContainer, MessagePipe, UniTask or an MVS split, in
either condition.

Three things worth carrying:

**A contradiction resolved in the project file is resolved, not merely noted.** EE's `CLAUDE.md` says
"if a Kinglet rule contradicts what's above, this section wins," names the four diverging concepts,
and states that the rest still applies in full. That sentence does the whole job. The precedence
declaration is not documentation of an intent — it is the mechanism, and it works.

**The clincher is what condition B did.** With `architecture.md` deleted, one run still opened with
"Follow this project's architecture, **not `.claude/rules/architecture.md`**." It rejected a file that
was not there, because `CLAUDE.md` names it. The override is carried entirely by the override; the
rule's presence is not load-bearing in either direction. Removing it would not change a single
answer — it would only stop paying for it.

**Size is not influence, and I had used size as a proxy for harm.** "15.4 KB, 68% inapplicable,
loaded every session" is a real measurement that predicts nothing about output. The cost is input
tokens, which is a budget question; the concern I actually raised was correctness, which is a
behaviour question, and the two do not follow from each other. I reached for the file that was
easiest to *count*.

So the recommendation reverses: **leave it.** The measured harm is zero, and the 31% that does apply
here — `ScriptableObjects for Static Data`, `Input System Architecture`, `No God Objects`,
`Composition Over Inheritance` — is cited by the answers themselves. Cutting the file to save
context would trade a real 4.9 KB of used guidance for a hypothetical saving on 10.5 KB the model
demonstrably ignores.

**The general form:** before optimising away context that looks wrong, run the cheap A/B. Six
headless runs and twenty minutes turned a confident architectural argument into a negative result.
The negative result is the more valuable outcome — it retires the question instead of trading one
guess for another.

## 88. The execution loop's first real run, and the three things it got wrong

The `subagent-driven-implementation` skill shipped on 2026-08-04 describing a loop this repository
had run by hand seven times the day before. Writing it down is not the same as knowing it works, so
it was run once, for real, on a task chosen from the carried-findings list.

The intended subject — a hook printing a pre-flattening skill path — had already been fixed by an
earlier task in the same wave, which is its own small lesson about picking trial subjects from a list
written before the wave started. The replacement was measured rather than guessed: `assert_eq` in
`tests/run-tests.sh` declares `(expected, actual)`, and across 141 call sites, 58 passed the
expectation first and 33 passed it second. A third of the suite appeared to print its two failure
labels backwards — and this wave read those labels constantly, six times reintroducing a defect in a
worktree specifically to watch a guard name it.

### What the run got wrong, in the order it mattered

**1. The brief's premise was false, and the loop has no step for that.** The task was framed as "make
every call site agree with the helper." There is no single helper. Seven test files define their own
unconditional local `assert_eq()` that shadows the exported one for the rest of their subshell, and
its message reads `expected '$2', got '$1'` — **the opposite contract, under the same name, in the
same suite.** The 58/33 split was not sloppiness; it was two conventions.

The implementer's first pass swapped 49 call sites on the brief's premise, then caught the error by
probing a failure in a scratch worktree and reverted 29 of them. Net standing change: 20 call sites in
the 5 files that genuinely use the runner's helper.

That recovery is the loop working. But the skill says what to do when a *review* finds a problem and
nothing about when the **brief** turns out to be wrong — and a brief written by the controller carries
more authority than one written by a reviewer, so it is the more dangerous of the two to be wrong.
The Task 4 implementer had already flagged the adjacent rule ("at the cap, adjudicate") as stating
what not to do without a sharp test. This is the same softness reached from the other side.

**2. Both roles are hardcoded to Unity agents, and a Unity project's plan is not all Unity.** The
skill names `unity-coder` as the implementer and `unity-reviewer` as the reviewer. This trial was bash
in a repository that is not a Unity project, so both were the wrong fit and the deviation had to be
recorded before the run started. That is not a quirk of the toolkit's own repository: a real Unity
project's plan routinely contains build scripts, CI, editor tooling and documentation tasks, and the
loop currently routes all of them to an agent that writes C# and drives the Editor over MCP.

**3. Picking the trial subject from a list is how you measure the wrong thing.** The carried-findings
list was written before the wave and the wave had already closed the entry. Choosing the subject from
a fresh measurement — counting the actual call sites — produced both a real task and a finding the
list did not contain.

### What it got right, and why that is the part to keep

The instruction that saved the run was *"verify by making a failure happen, not by reading the diff."*
The implementer broke the checked condition in a throwaway worktree and read the printed labels. A
diff review would have shown 49 tidy, consistent-looking swaps and approved them.

Six times in two days, that same method has been the thing that distinguished a guard that works from
a guard that reports success. It is the single most load-bearing sentence in the skill and it should
be the last thing anyone trims.

### Parked, with a ruling

Two `assert_eq` contracts under one name is a real defect and it is not fixed. It is not load-bearing:
the suite is green, every assertion compares the right two values, and only the *labels* in seven
files read against the runner's convention. Fixing it means changing seven function definitions and
re-inverting the call sites that currently match them — a change whose own failure mode is the one
that just bit this trial. It belongs in a wave with room to probe it, not at the end of one.

Recorded here rather than in a ledger that gets deleted, because the next person to touch a test
helper in this repository needs to know that `assert_eq` means two different things depending on
which file they are in.

## 89. The loop's first run on a real game, and what 33 subagents proved about the Skills block

§88 recorded the execution loop's first run — on this repository, on its own toolkit. On 2026-08-04
it ran on a real Unity game: the skin system in Endless Evolution, twelve tasks (T01–T09 plus three
opened mid-run), 47 commits, EditMode 1242/1242 and PlayMode 741/741 at the end. Thirty-three
subagents were dispatched. Their transcripts are on disk, so the questions this note answers are
counted rather than argued.

### The Skills-to-load block is obeyed. That is the finding, and it is the problem.

| Agent | n | Skills it loaded |
|---|---|---|
| `unity-coder` | 12 | `assembly-definitions` 12/12, `verification-before-completion` 12/12, `object-pooling` 7 (self-selected) |
| `unity-reviewer` | 17 | `object-pooling` 7 — and nothing else, ever |
| `general-purpose` | 4 | none |

**Every implementer loaded both skills its block named, without exception**, and seven reached past
the block for a third. This is the first hard evidence that the block works: the mechanism this
toolkit relies on — an explicit list plus `Skill` in `tools:`, with nothing loading implicitly —
does what it claims.

Which makes the second row expensive. `unity-reviewer`'s block named exactly one skill,
`object-pooling`, so seven reviewers loaded a pooling guide before reviewing ScriptableObject
authoring, a save schema and a time-trial rule — and the other ten, reading a mandate that plainly
did not fit, loaded nothing at all. **No reviewer in the entire run ever loaded
`verification-before-completion`**, the skill that tells it what the implementer's evidence is worth.

The 2026-08-03 second pass had already found the gap — "no agent's block names
`systematic-debugging` or `verification-before-completion`" — and the fix reached four agents of
eight. `unity-prototyper`, `unity-scene-builder`, `unity-ui-builder` and `unity-reviewer` were
missed. Same shape as the duplicate `## Project Facts` heading: the argument was made once and
applied on one side only. `tests/test-surface-references.sh` now asserts all eight.

The general lesson is narrower than "put more skills in the block": **agents follow the block
literally, so a mandate that does not fit the job is not ignored — it is either obeyed at a cost or
it teaches the agent that the block is advisory.** Both outcomes are worse than an empty list.

### A unity-mcp success flag is not a written value

Authoring twelve ScriptableObjects, `manage_scriptable_object` **rejected** the array-resize patch —
`Unsupported SerializedPropertyType: ArraySize` — and then reported **success on all twelve element
writes into that same array.** Nothing logged, `read_console` clean. The implementer distrusted the
flags, read the `.asset` back from disk, and only then knew the state.

Same shape as a `.cs` file that fails to compile: the write succeeds, the outcome does not, and only
a second look distinguishes them. Now Rule 7b of `unity-mcp-patterns` and a row in
`verification-before-completion`.

### What the controller had to invent, which means the skill should have supplied it

The ledger grew two sections the skill never asked for, and both earned their place:

- **Standing facts for every dispatch.** A fresh subagent inherits none of the controller's reading
  of the project. The controller wrote out, every time, that this project uses singleton services and
  hand-rolled FSMs with no VContainer/MessagePipe/UniTask and that coroutines are the async primitive
  — because `CLAUDE.md`'s generated block is a thing the *controller* read, not a thing the
  implementer inherits. The first implementer also lost a suite run to a repository rule requiring
  every new runtime script to be named by some subsystem document; once that was standing, the
  remaining eleven tasks never met it again.
- **Interfaces produced so far.** It caught a real trap: two new types exposed *properties* while the
  sibling type the brief compared them to used public *fields*, so a brief saying "same as
  `LevelGraph`" would have been wrong.

Both are now in the skill's Setup, and the standing facts are item 3 of the implementer dispatch.

Two smaller ones, also adopted: write later-stage briefs **just before dispatch** (a brief written
against a signature that does not exist yet is a brief that gets withdrawn, and by the skill's own
step 5 a withdrawn brief costs a whole task), and **cite by test name, not line number** — a
controller forwarded a citation to lines 410–423 of a 378-line file.

### The reviewer's blindness is load-bearing, and the controller worked it out unaided

`unity-reviewer` has no Bash and no MCP — only `Read`, `Glob`, `Grep`, `Skill`. The controller
described this as a design that shapes the loop rather than a gap: the reviewer cannot drive the
Editor, so it must read the code, and must mark `⚠️ Cannot verify from diff` for what it cannot
confirm. It also explains why the controller states gate and suite results in every review dispatch
— the reviewer cannot run them, and if it could it would burn two minutes per task re-running a
suite the dispatch could state in one line. It twice reached for a `general-purpose` reviewer
instead, for findings that needed an *experiment* rather than a reading. The prompt already said all
of this; that a fresh controller re-derived it from the tool list is evidence the constraint is
legible in the design, not only in the prose.

### Still open: the chain names behaviour that then happens without the chain

The controller again did not invoke `deep-interview`, and again performed the interview — two rounds
of questions, decisions written to a design document. `using-kinglet` is injected every session and
its table describes each process skill well enough that a capable model executes the behaviour
without loading the file. The outcome is right and the escape-hatch sections nobody loads are the
Wave-2 investment that has now gone unread twice. §87 is the neighbouring measurement; this is not
settled, and it wants a probe rather than another edit.
