# Goal Checkpoint Ladder (slice B1) — Design

* **Issues**: [#13](https://github.com/bnaylor/iris/issues/13) (inner/outer loop semantics) — the **checkpoint half**. Builds on merged **slice A** ([2026-07-28-goal-contract.md](2026-07-28-goal-contract.md)) and **slice C** ([2026-07-29-goal-drift-evaluator.md](2026-07-29-goal-drift-evaluator.md)).
* **Date**: 2026-08-01
* **Status**: Approved (design)

## 1. Overview

Slice A gave a goal a locked **contract** with a flat list of criteria; slice C added a **fresh-context evaluator** that produces a trusted per-criterion verdict. Today a long goal still runs to a single terminal `goal_complete` — the human has no sanctioned point to re-engage mid-goal (A §2 called this out as a conscious v1 limit and assigned the fix to B).

B1 adds the **milestone ladder**: an ordered sequencing of the contract's *existing* criteria into groups, each ending in a **checkpoint** where the loop hard-stops, the C evaluator grades the work so far, and the human decides whether to advance. The ladder is a *view over criteria A and C already established* — it introduces no new definition of "done."

## 2. Scope of this slice (B1: the checkpoint ladder)

B1 **sequences** the contract into ordered human-re-engagement points and **pauses + grades** at each. It does **not** formalize subagent delegation, and it does **not** automatically block or auto-retry on a verdict.

**Split from #13 (deliberate).** #13 has two halves. B1 is the checkpoint/milestone ladder only. The other half — formalizing outer (main agent holds the contract, delegates) vs inner (subagent builds a bounded unit, reports a structured result) loop semantics and the context boundary between them — becomes a later **B2** spec. This split is clean because subagents set `activeGoal` with **no** `goalContract` (SubagentManager §), so `hasLadder` is false for them and checkpoints never engage; B1 is therefore main-agent-only by construction, not by a guard.

**Honesty boundary (stated up front).** A checkpoint pause surfaces two things side by side: the agent's **self-report** for the milestone (unverified — same context that did the work) and the **trusted verdict** from a fresh C evaluator run. B1's value is creating the *re-engagement point* with trustworthy evidence at it; the human, not the loop, decides what to do with that evidence.

**Explicitly deferred (deliberate, not silent omissions):**
- **Automatic gating on a verdict → slice D.** In B1 a `not_met` checkpoint verdict does **not** block the run or auto-reprompt the agent. It is presented; the human chooses to advance or send back. Wiring the verdict into an *automatic* block/soft-retry requires D's retry cap + `n/a — <reason>` escape hatch — building auto-retry without them ships *trapped goals* (the same reasoning C §2 used to defer gating).
- **Inner-loop subagent formalization → slice B2.** Structured inner-loop results, bounded units, and the outer/inner context boundary are B2. B1 touches neither `SubagentManager` nor subagent behavior.
- **Delegating a milestone to a subagent → B2.** A checkpoint could later hand its milestone to an inner loop; B1 keeps the main agent working every milestone itself.
- **Cross-goal / persistent ladders → out of scope.** The ladder lives on the `Conversation`'s contract and ends with the goal, exactly as A §8 scoped the contract.

## 3. The milestone ladder

A goal's criteria are the flat definition-of-done. A **milestone** is an ordered group of those criteria with a short human title. The milestones form an **ordered partition** of the criteria: each criterion belongs to exactly one milestone, and every criterion belongs to some milestone.

- **Ordered** — milestone order is the sequence the loop works through; the checkpoint after milestone *N* re-engages the human before milestone *N+1*.
- **Partition** — disjoint (a criterion lives in one milestone) and covering (no criterion is left out). This makes "grade this checkpoint" unambiguous.
- **Optional** — zero milestones means no ladder, and the goal behaves exactly as it does today: a single run to terminal `goal_complete`. A small goal needs no ladder.

The ladder adds **no new criteria and no per-milestone sub-objectives** — that would reintroduce the self-authored-target problem C exists to distrust. A milestone's only "done" definition is the subset of contract criteria it owns.

## 4. Data model

Two new types and three new fields on `GoalContract`, all `decodeIfPresent`-defaulted so a legacy contract decodes to an empty ladder (§7 migration):

```swift
struct Milestone: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var title: String
    var criterionIds: [UUID]   // a disjoint subset of contract.criteria; ordered position = ladder order
}

enum CheckpointStatus: String, Codable, Sendable, Equatable {
    case running          // loop active (or no ladder)
    case pausedForReview  // reached a checkpoint; auto-reprompt suppressed, awaiting the human
}

// GoalContract gains:
var milestones: [Milestone] = []          // empty ⇒ no ladder ⇒ today's single-terminal behavior
var currentMilestone: Int = 0             // index of the milestone being worked; advanced on resume
var checkpointStatus: CheckpointStatus = .running
```

**Invariants (enforced in code, not prose):**
- **Partition at lock.** Locking a contract with a ladder validates that `milestones` criterionIds are disjoint and cover all `criteria`. The panel flags unassigned criteria before lock (§8).
- **Robust load.** On decode of a hand-edited or legacy contract, any criterion assigned to no milestone folds into an implicit **final** milestone, and `currentMilestone` is clamped to `0..<max(1, milestones.count)`. The ladder never crashes on bad data.
- **`currentMilestone` monotonic.** It only ever advances (on human "approve & continue"), never rewinds automatically.

**Helpers on `GoalContract`:**
- `var hasLadder: Bool { !milestones.isEmpty }`
- `var isFinalMilestone: Bool { currentMilestone >= milestones.count - 1 }`
- `func currentMilestoneCriteria() -> [Criterion]`
- `func projectedContract(throughMilestone n: Int) -> GoalContract` — a **locked** copy whose `criteria` are the cumulative set across milestones `0...n`, with `milestones` emptied. This is fed to `GoalEvaluator.evaluate()` **unchanged** — checkpoint grading is C run on a projection (§6).

## 5. Trigger — the `reach_checkpoint` tool

A new tool, structurally a sibling of `goal_complete`, **offered only when `hasLadder`** (filtered out of the toolset otherwise, so a no-ladder goal's surface is identical to today):

```
reach_checkpoint(milestone_summary: STRING, criteria_status: <same per-criterion self-report shape as goal_complete>)
```

The **oracle** (`GoalContract.oracleText()`, injected each iteration per A §6) is extended when `hasLadder`: it renders the **current milestone** as the immediate target ("Current checkpoint: *title* — the criteria below are this checkpoint's definition of done"), lists the remaining ladder for context, and instructs: **call `reach_checkpoint` at each non-final milestone; call `goal_complete` only when the final milestone's criteria hold.**

`goal_complete` semantics are **unchanged** — it remains the sole terminal path that clears the goal, fires the completion self-report + C grade, and triggers the skill-check reflection. This is deliberate: A §6 and C flagged `goal_complete` / the #16 soft-stop machinery as a fixed constraint. B1 adds a parallel intermediate signal rather than overloading the terminal one.

## 6. Checkpoint handler flow

In `iris.swift`, beside the `goal_complete` handler (~L790):

1. **Final-milestone guard.** If `isFinalMilestone`, return guidance: "This is the final milestone — call `goal_complete` to finish." Terminal stays a single path. The final milestone's criteria are therefore graded by the existing terminal `goal_complete` C run (the whole contract), so every criterion still receives a trusted grade — no criterion falls between the last checkpoint and completion.
2. **Record self-report.** Persist the milestone's per-criterion self-report, marked *unverified* (reuse A's `recordCompletionSelfReport` shape, scoped to the milestone).
3. **Grade cumulatively.** Build `projectedContract(throughMilestone: currentMilestone)` — the cumulative criteria across milestones `0...currentMilestone` — and `await GoalEvaluator.evaluate()` on it. **Awaited, not detached** (unlike `goal_complete`'s background grade): the loop is pausing anyway, and the human should see the verdict *before* re-engaging. Cumulative grading catches **regressions** — milestone *N*'s work breaking an earlier milestone's criterion — which is the entire reason a checkpoint is a gate and not just a status print.
4. **Pause.** Set `checkpointStatus = .pausedForReview`. `activeGoal` **stays set** — the loop gate (A §6) is untouched.
5. **Suppress the loop.** The auto-reprompt block (iris.swift ~L662–692) gains one guard: if `checkpointStatus == .pausedForReview`, end the turn — no reprompt, no soft-stop fallback. Pause is a suppression layer **above** #16's machinery, not a replacement for it: while paused, both the auto-reprompt and the soft-stop summary path are quiet.
6. **Surface.** Post the milestone summary (unverified) + the trusted verdict (from step 3) + ladder position ("Paused at checkpoint *N+1* of *count*"), then the turn ends and the loop waits.

## 7. Resume (human-driven; B1 does not auto-gate)

At the pause the human sees the self-report and the trusted verdict side by side and chooses. **There is no automatic block or auto-retry — that is slice D.** B1 only creates the re-engagement point:

- **Approve & continue** (panel action) → `currentMilestone += 1`, `checkpointStatus = .running`, re-arm the loop with a reprompt aimed at the next milestone.
- **Send back / steer** (the human types feedback, or simply wants the agent to keep working the current milestone — typical when the verdict has `not_met` criteria) → `checkpointStatus = .running`, `currentMilestone` **unchanged**, reprompt carries the human's steer plus the `not_met` criteria + evidence from the verdict. This is a *human-initiated* retry within the milestone, not an automatic gate.

Because `checkpointStatus`, `currentMilestone`, and the whole contract persist on `Conversation.goalContract`, a **restart while paused** reloads the paused chip and the loop stays quiet (the reprompt guard reads `checkpointStatus`) until the human resumes — a partial answer to [#61](https://github.com/bnaylor/iris/issues/61) that falls out for free.

## 8. Authoring & UI

**Authoring (drafted with the contract).** During `/goal` negotiation the model proposes milestones alongside criteria; the proposal is parsed in `GoalContractParsing`. The draft is fully editable: the user adds / reorders / removes milestones and assigns each criterion to one, in `GoalContractPanel`. An **unassigned-criteria warning** blocks lock until the partition is complete (or the user chooses "no ladder," clearing milestones). The ladder locks together with the contract.

**Locked run (`GoalContractPanel`).** A compact ladder view shows milestones as **done** (advanced past), **current**, and **upcoming**. At a pause the current rung highlights with its checkpoint verdict and the two resume affordances (§7). Milestone self-reports render **unverified** (reusing A's honesty marking) until the checkpoint grade lands, then show C's verdict beside them (reusing C's verdict rendering). A must-not: never present a milestone self-report as a passed gate.

## 9. Error handling & edge cases

- **`reach_checkpoint` with no ladder** → tool is not offered; if somehow called, no-op with guidance to use `goal_complete`.
- **`reach_checkpoint` on the final milestone** → routed to `goal_complete` guidance (§6.1); terminal stays single.
- **Evaluator fails at a checkpoint** (grader ended without submitting) → the existing safety net records a `failed` evaluation; B1 still pauses and presents the failed status honestly. The human decides.
- **Hand-edited / legacy contract** → unassigned criteria fold into an implicit final milestone; `currentMilestone` clamped (§4).
- **Amend during a pause.** `amend_goal_contract` still works while paused; a criterion added must be assigned to a milestone (default: the current milestone) to preserve the partition invariant, and a removed criterion is dropped from its milestone. Both remain change-logged with a rationale (A §4).
- **Subagent goal** → no `goalContract`, so `hasLadder` is false; checkpoints never engage (§2).

## 10. Interaction constraints (fixed, not a blank slate)

- **#16 soft-stop machinery** (loop detection, iteration cap, auto-reprompt, soft-stop summary — all gated on `activeGoal != nil`) is **unchanged**. The pause is a new suppression layer above it.
- **`goal_complete`** semantics are **unchanged** — still the only path that clears the goal, self-reports, triggers the background C grade, and fires the skill-check reflection.
- **`GoalEvaluator.evaluate()`** is reused **unmodified**; checkpoint grading only constructs a projected sub-contract to hand it.
- **`SubagentManager`** and subagent behavior are **untouched**.

## 11. Testing

**Pure / unit-testable:**
- `Milestone`/ladder Codable round-trip; `decodeIfPresent` backwards compat (legacy contract → empty ladder → today's behavior).
- Partition validation: disjoint + covering accepted; a gap rejected at lock; a hand-edited gap folds into an implicit final milestone on load; `currentMilestone` clamped.
- `projectedContract(throughMilestone:)` returns the cumulative criteria across `0...n`, locked, with `milestones` emptied.
- `oracleText()` with a ladder renders the current milestone as the target + the remaining ladder + the reach_checkpoint/goal_complete instruction.

**Handler / loop (driven by `ScriptedLLMClient`, as C's tests are):**
- `reach_checkpoint` sets `pausedForReview`, does **not** clear `activeGoal`, and invokes the evaluator on the projection.
- While `pausedForReview`, the auto-reprompt does **not** fire (assert the loop is quiet).
- Final-milestone `reach_checkpoint` routes to `goal_complete` guidance.
- **Approve & continue** advances `currentMilestone` and re-arms the reprompt toward the next milestone.
- **Send back** keeps `currentMilestone` and reprompts with the `not_met` evidence.
- Restart while paused: the contract reloads `pausedForReview` and the loop does not auto-reprompt.

## 12. The larger arc (where B1 sits)

Per the slice-A roadmap (A §7), B1 is the checkpoint half of **B**. Remaining, in dependency order:
- **B2 — inner/outer loop semantics (#13 remainder):** formalize outer vs inner loops and the context boundary; a checkpoint may then delegate its milestone to a bounded inner loop.
- **D — deterministic done-gates:** consume C's verdict *automatically* — block `goal_complete` / auto-soft-retry unless graded-pass or a stated `n/a — <reason>`, guarded by a retry cap. B1's human-driven resume is the manual precursor; D makes the gate automatic and safe.
- **E — the ratchet**, **F — ground-truth progress view** — independent, per A §7.
