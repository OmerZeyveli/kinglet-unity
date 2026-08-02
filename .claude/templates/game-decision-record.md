<!-- Kinglet Pioneer game decision record (GDR). Authored copies go to docs/decisions/. -->

# Game decisions, [YYYY-MM-DD]

> **This is not an ADR.** An ADR decides how a system is built (see
> `architecture-decision-record.md` — engine domain, interfaces, frame budgets). A GDR decides what
> the game *is*: whether a mechanic exists, what it may not do, and what it costs. If your decision
> has a `CBUFFER` in it, you want the ADR. If it has a player in it, you want this.

Answers to questions the work refused to answer for itself. Each is written so an implementer, a
level designer, or a parallel track can act on it **without asking a second question**.

---

## Standing decisions no one may relitigate

<!-- MANDATORY. The rules already settled, that every decision below assumes and no implementer may
     quietly reverse. Copy them here verbatim rather than linking — a link does not survive a fresh
     agent's context. Give each a one-line reason, because a rule without a reason gets argued with. -->

- **[Rule]** — [why it holds]
- **[Rule]** — [why it holds]

> A finding, plan, or agent proposal that contradicts one of these is wrong by construction. Say so
> and close it; do not implement it and do not escalate it as an open question.

---

## N. [The decision, stated as a claim — not "Water in the cave?" but "The cave has no water"]

**Question.** [What was actually unclear, and why it blocked something. Name what was blocked.]

**Decision: [one sentence, imperative, unambiguous].**

**Why.** [The reasoning that would let a reader re-derive this decision from scratch. If the reason
is structural — "this mechanic is the same object as one we already have, wearing a different
costume" — say the structure out loud. Reasons age better than conclusions.]

**Evidence.** [OPTIONAL but strongly preferred where the decision turned on how the game actually
behaves rather than on taste. Cite it the way a finding is cited: `file.cs:LINE`, the asset path, the
authored value. A design decision resting on a belief about the code that is not true is the most
expensive kind of decision to discover late.]

**What this does NOT decide.**

<!-- MANDATORY. The single field that does the most work. Without it, a decision expands to fill
     every adjacent question and two implementers reach opposite readings of the same sentence. -->

- [Adjacent question this leaves open, and who owns it]
- [Reading someone might take from this that is NOT licensed by it]

**What it costs, stated plainly.** [The thing that gets worse. Every real decision has one; a
decision with no cost was not a decision. If the cost is borne by a specific feature or form, name
it.]

**What would reverse this.** [OPTIONAL. The concrete observation that should make someone re-open
it — "if playtesters read the shaft as a dead end", "if the second body costs more than one sprint".
Write it now, while you still remember what you were unsure about.]

---

## Provisional — decided, but weakly

<!-- OPTIONAL. Decisions taken to unblock work, that the owner has not actually committed to. Keeping
     them separate is the point: an implementer must be able to tell "this is settled" from "this is
     settled *for now*" without asking. -->

- **[Decision]** — provisional because [what is unknown]. Revisit at [the concrete trigger].

---

## Deferred — not decided

<!-- OPTIONAL but expected. A deferral is a decision and carries consequences like any other.
     "We'll decide later" without the consequence is how a gap ships. -->

- **[Question]** — deferred. **Consequence of deferring:** [what now has to work without it, and
  what compensates].

---

## Open questions for the owner

<!-- OPTIONAL. What still blocks. One line each, phrased so it can be answered with a sentence. -->

- [Question]
