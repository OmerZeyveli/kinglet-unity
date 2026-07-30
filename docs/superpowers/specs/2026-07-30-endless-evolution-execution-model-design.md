# Endless Evolution — execution model for the hardening work

**Date:** 2026-07-30
**Status:** approved, ready for planning

## The question

Two rounds of four parallel remote-control terminals have run against Endless Evolution. The
infrastructure phase is finished. The remaining work is large and heterogeneous. Should it continue
as four terminals, collapse to one session driving subagents, or something else?

## What the two rounds measured

Same agents, same operator, same prompt discipline, ten-fold difference in output:

| | Shape of work | Result |
|---|---|---|
| **Round 1** | Four independent read-only sweeps, one per source directory | 30+ commits, every track productive throughout |
| **Round 2** | Three tracks whose work depended on a fourth track's deliverable | 5 commits; one track produced nothing; one track, forbidden from writing docs, wrote docs |

The variable was not the agents. **Parallelism pays for breadth and loses money on bottlenecks.**
Round 2's failure was a work-selection failure, not a model failure — three terminals were handed
work gated on an unlock that never arrived.

Three further defects surfaced only at integration, and each is invisible inside a single track by
construction:

- three tracks each added a source file and each omitted the same subsystem-doc update;
- two tracks independently performed the same task (repointing the compile gate in documentation),
  which then presented as a merge conflict;
- a stale, orphaned, gitignored project file made the compile gate meaningless for two rounds.

## Constraints

- The operator is present and responsive but remote, driving this session plus four remote-control
  terminals from a browser. They are the message bus between sessions: relay is possible and fast,
  but it is not free and it is lossy.
- Quota consumption is a goal, not a cost. Idle capacity is waste; make-work is worse than waste.
- Quality is not negotiable against speed.

## The decision

### Terminals carry deep work; subagents carry wide work; the two are different tools

| | Remote terminal | Dispatched subagent |
|---|---|---|
| Context | Its own window, persists for hours | One-shot; dies when it returns |
| Iteration | try → fail → fix → retest, many cycles | Must complete in a single dispatch |
| Coordination | Through the operator — slow, lossy | Free; the dispatcher sees every result |
| Operator cost | Paste, monitor, relay | None |

The remaining work splits cleanly along that axis. A singleton seam — extract, write the test that
was previously impossible, mutation-verify it, watch it fail, fix, re-run — is a multi-cycle task
that needs persistent context. Applying one of 102 catalogued findings is the same shape every time
and completes in one pass.

So the framing "terminals *or* subagents" is wrong. **Terminals carry the deep work and fan out to
their own subagents for the wide work inside it.** Four terminals each dispatching subagents is
strictly more capacity than one session dispatching subagents, and it keeps every unit of consumed
quota attached to real work.

### This session stops being a worker

The largest waste in round 2 was that one session was simultaneously the integrator and a
contributor. Every merge, every conflict resolution, every Unity pass and every verification queued
behind the same turn order that was also trying to produce work.

**This session is the integrator and auditor. It does not take a track.**

### Tracks self-merge; this session audits rather than gates

This was not safe in the morning and is safe now, because the gate that replaced it was built during
the session. A `pre-push` hook (wired via `core.hooksPath` to a tracked directory) runs, in
cheapest-first order: source-layout check → compile gate with its file-set assertion → EditMode suite
→ PlayMode suite. Everything mechanical now passes through automation on every push.

Two classes of defect remain that automation cannot catch, and both are audit work rather than gate
work:

- **A plausible but wrong claim.** A documentation citation was changed from `DeathState.OnEnter` to
  `DeathState.Enter`; the method that does the work is `Exit`. Every automated check passed, because
  `Enter` does exist in that file. Only reading the source settled it.
- **Semantic duplication between tracks.** Two agents cannot see each other.

Standing as a serial gate in front of every merge was what created the queue. Auditing continuously
behind the gate does not.

### Integration interval

Each track merges to `hardening/base` as soon as **one unit of work is green**, not at the end of a
session. All three integration defects above scale with how long tracks stay apart: a duplicate task
is caught the moment the second agent pulls, and a documentation gap fires the drift test on the
next merge rather than the last one.

## Track allocation

Each track owns disjoint directories and has a full session of independent work. Verified against
the planning test below.

**Numbering is preserved for directory ownership, not for context.** Each terminal's branch already
owns disjoint ground — terminal 2 in `Assets/Core/`, terminal 3 in `Assets/Player/` and
`Assets/Enemies/` — and that ownership is what keeps merge conflicts rare. It is git state, so it
survives anything done to the conversation.

**Each terminal is cleared before this wave starts, and again after each merge.** Not compacted —
cleared. Everything load-bearing is on disk: the branch, the commits, and each track's own
`docs/hardening/track-*-report.md`. What lives only in conversation is the track's accumulated
reasoning, and the evidence is that it hurts. Track 2 spent eight of nine commits on documentation in
round 1, then produced one documentation commit in round 2 *while explicitly forbidden from writing
any* — a groove the context carried forward. This is the same principle as fresh-implementer-per-task:
the context that makes an agent fluent also makes it repeat itself.

Compaction is worse than clearing here, because it preserves part of the groove as a lossy
model-written summary. The report files are better memory than a compaction artifact: they were
written deliberately, for a reader.

**The condition this imposes on every prompt:** a cleared terminal no longer remembers what it already
tried and rejected. Track 4 declined five §4.2c seams with a stated blocker for each; cleared, it
would re-attempt them. So every prompt must name the track's own report file as required reading
before it starts.

| Track | Work | Shape |
|---|---|---|
| **1** (tooling / infrastructure) | Repair `PerfCleanupTools.ValidateScenes`, then resolve the 69 missing-script references; cloud CI if the Unity licence arrives | Mixed |
| **2** (`Assets/Core/`) | The nine remaining singleton seams | Deep, cyclic |
| **3** (`Assets/Player/`, `Assets/Enemies/`) | Real PlayMode behaviour tests — FSM transition conditions against live physics, `TimeScaleService`'s blended lerps, `PauseService` surviving a scene load | Deep, cyclic |
| **4** (`Assets/Environment/`, `Assets/Editor/`, `docs/`) | The 102-finding backlog with heavy subagent fan-out, plus the two disclosed holes in the documentation-map test: bare type-name validation, and signature checking for `Type.Member` citations | Wide, shallow |

Track 4's second item is what would have caught the `Enter`/`Exit` defect: the map test currently
checks that a documented member *name* appears in its declaring file, which cannot distinguish a
citation that is wrong from one that is absent.

Track 1's first item is the same defect class the whole session has been chasing: `ValidateScenes`
opens every build scene, counts missing scripts, writes the total to its report, and **exits 0
regardless** — `PerfCleanupTools.cs:52` gates on `openFailures == 0 ? 0 : 2` and never consults
`totalMissing`. A validator that reports "clean" when it found breakage. The 69 missing references it
is supposed to guard are themselves unverified: they do not appear as `m_Script: {fileID: 0}`, so
finding them means resolving script GUIDs against `.meta` files rather than grepping.

### The planning test this allocation had to pass

> If any one track returns nothing at all, does every other track still have a full session of work?

Yes for all four. This question is cheap to ask and was the entire difference between round 1 and
round 2; it belongs in the planning step permanently.

## Prompt rules carried into every track

Derived from observed behaviour, not from principle:

1. **Merge to `hardening/base` when one unit is green.** Do not diverge for a session.
2. **If you do not do something you were asked to do, write it down with the reason.** One agent
   delivered two of four items and its 947-line report mentioned neither omission. Not finishing is
   normal; not saying so is not.
3. **Read the source before you "fix" a name in a document.** See the `Enter`/`Exit` case above.
4. **Challenge the brief.** The best work in round 1 came from an agent that measured a handed-down
   diagnosis instead of implementing it — establishing the coupling was one-way rather than mutual,
   and rejecting a proposed interface name that "would be a lie at precisely the point a bug would
   hide."
5. **Behaviour-changing work needs a test that fails before and passes after; non-behavioural work
   needs the compile gate and a diff small enough to read.** "No test, no fix" applied bluntly would
   freeze roughly 130 of 137 findings that are dead code, unused fields, or lying comments.

## Out of scope

- Cloud CI activation. It is written and merged; its test jobs stay skipped until the operator
  supplies a Unity licence secret. The `pre-push` hook covers the interval and the decision is the
  operator's.
- A direction-enforcing multi-assembly split. One runtime assembly is sufficient for PlayMode; a real
  split is a separate and much larger job.
- Playtest-driven or feel-related verification. It requires the operator at the machine.

## Success criteria

- Every track merges at least once per unit of work rather than once per session.
- No defect of the three integration classes above survives to a session boundary.
- This session performs no track work.
- `hardening/base` stays green on all four gates after every merge.
