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
