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

## 8. Smaller things worth carrying

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
