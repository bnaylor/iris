# Goal Contract — Design

* **Issues**: [#13](https://github.com/bnaylor/iris/issues/13) (inner/outer loop semantics) and [#9](https://github.com/bnaylor/iris/issues/9) (dynamic gates + impartial evaluator) — this is the **first slice** of a larger arc; see §7.
* **Date**: 2026-07-28
* **Status**: Approved (design)

## 1. Context & Philosophy

Driven by two field docs (`~/roman/hurricane.md`, `~/roman/warpspeed.md`). The transferable core: **rely on the tool, not the model** — the behaviors you must count on are enforced by the harness (code + data), not left for the model to remember. When writing code is cheap, the bottleneck is *judgment*: choosing what to build and knowing whether it's right. Discipline (contracts, gates, impartial evaluation) is what makes a loop trustworthy — and, later, what makes autonomy safe.

**Decided direction: discipline-first, opt-in via `/goal`.** Normal chat is untouched. `/goal` is the mode where structure applies. Autonomy is a later *dial*, not a rewrite — every gate built here is exactly what a more-autonomous loop would need. Explicitly out of scope for the whole arc (per user): breeze-style overnight autonomy, an org-scale portal, and `/shared/agents` export.

## 2. Scope of this slice (A: the Goal Contract)

Turn `/goal <one line>` from a plain string into a structured, lockable **contract** that becomes the loop's decision oracle. This slice makes the contract *exist, be consulted, and be reported against*. It does **not** yet add the trusted, independent grader — that is slice C (§7).

**Honesty boundary (stated up front so we don't fool ourselves):** consulting a locked contract reduces "built the wrong thing," but a goal's completion self-report is produced by the *same* context doing the work. That is transparency, **not** a trusted grade. The drift *gate* — a fresh context verifying the work against the locked contract — is slice C. This spec must not claim to prevent drift on its own.

**Explicitly deferred from this slice (deliberate, not silent omissions):**
- **Checkpoints / milestone ladder** — the ordered stop points where the human re-engages mid-goal are a loop-structure concern and belong to slice B (§7). A's criteria are the *flat* definition-of-done that B will later sequence into checkpoints. Consequence: in A a long goal runs to a single terminal `goal_complete`, with no intermediate human-re-engagement points beyond the existing `stop-before` boundaries and #16's loop guards. This is a conscious v1 limit, called out here so it isn't mistaken for an oversight.
- The trusted grader (C), done-gates that block completion (D), and the rest of §7.

## 3. The criteria spectrum (fuzzy goals are first-class)

A goal's "definition of done" is a list of criteria, each tagged by how it can be judged. **No fabricated numbers** — that would violate Iris's existing honesty invariant. Mirrors the grader hierarchy in the field docs (executable → judged → human):

- **`executable`** — carries a command/test whose pass/fail is machine-checkable (`swift test` green; "endpoint returns 200"). Highest trust.
- **`qualitative`** — a concrete "done looks like X" a fresh reader can judge without a number ("the twisty expands without the mis-paint"; "the reply cites its source").
- **`humanJudged`** — explicitly flagged "you decide" (taste, direction, contested architecture). The loop never pretends to grade these; it surfaces them for the human.

A goal with hard targets gets `executable` criteria; a fuzzy goal ("make `/goal` richer") gets `qualitative` ones; neither gets invented metrics.

## 4. Data model

A new `GoalContract`, persisted on the conversation (replacing today's `Conversation.activeGoal: String?` as the loop's goal state; see §6 for migration):

```
enum CriterionKind: String, Codable { case executable, qualitative, humanJudged }

struct Criterion: Codable, Identifiable, Equatable {
    let id: UUID
    var text: String              // "swift test passes" / "twisty repaints without scroll"
    var kind: CriterionKind
    var check: String?            // command/test for .executable; nil otherwise
}

struct ContractChange: Codable {  // §9 change-log: criteria change deliberately, never silently
    let date: Date
    let rationale: String         // one line: why the criteria changed
}

enum ContractState: String, Codable { case draft, locked }

struct GoalContract: Codable, Equatable {
    let id: UUID
    var objective: String                 // the one line you typed
    var criteria: [Criterion]
    var outOfScope: [String]              // explicit non-goals
    var stopBefore: [String]             // irreversible / authorization boundaries
    var assumptions: [String]            // what Iris inferred while drafting; confirm before lock
    var changeLog: [ContractChange]
    var state: ContractState
    // convenience: `isLocked`, mutation helpers that REQUIRE a rationale to edit criteria post-lock
}
```

**Invariant (testable):** once `state == .locked`, any edit to `criteria` / `outOfScope` must append a `ContractChange` with a non-empty rationale. Locked contracts cannot be mutated silently.

## 5. Creation flow — draft + confirm

`/goal <line>` (parsed today in `AppState.sendMessage`, ~L345) triggers:

1. **Draft.** Iris generates a full `GoalContract` (draft state) from the one line + conversation context — criteria (kind-tagged), out-of-scope, stop-before, assumptions. Drafting obeys the honesty invariant: never invent an `executable` `check` it cannot actually run, and prefer a concrete `qualitative` criterion over a fabricated number. The draft is the model's *proposal*; the human confirm (step 3) is the guard on draft quality — the one undisciplined step in the flow, deliberately gated by a human sign-off.
2. **Clarify — narrowly.** Iris asks **1–3 targeted questions only** where the goal is genuinely ambiguous or a boundary/authorization matters ("keep `List`, or allow a `LazyVStack` rewrite?"). Ambiguity is contained at the input, not discovered at the output. If the draft is unambiguous, no questions.
3. **Edit + approve → lock.** The user tweaks the draft (in the panel, §8) and approves. Approval sets `state = .locked`. The locked contract is the oracle.

Reversibility: before lock, the whole thing is freely editable / abandonable. After lock, changes go through the change-log.

## 6. Loop integration

The existing goal loop (auto-reprompt in `iris.swift`, gated on `activeGoal != nil`; `goal_complete`; `clearGoal`; loop-detection/soft-stop/`maxGoalIterations` from #16) consumes the contract:

- **Goal state becomes the contract.** `Conversation` gains `goalContract: GoalContract?`. The loop's "is a goal active" gate switches from `activeGoal != nil` to `goalContract?.isLocked == true`. `activeGoal: String?` is retained for backwards-compatible decode and derived from `goalContract.objective` (migration: an old persisted `activeGoal` string with no contract is treated as a locked single-`qualitative`-criterion contract, so in-flight goals survive an upgrade).
- **Oracle in context.** The locked contract (objective, criteria, out-of-scope, stop-before) is injected into the loop's reprompt/system context each iteration, so the agent consults criteria before decisions and treats scope/stops as hard edges. Criteria are the definition of "done."
- **`goal_complete` reports per-criterion status.** Its schema (`iris.swift` ~L334, currently a single `summary`) gains a structured per-criterion status: for each criterion, `met | not_met | cannot_verify` + a short evidence pointer (a test result, a file:line, a sentence). The free-text summary remains. This is a *self-report for transparency*, the input slice C will independently verify — **not** a trusted grade.
  - **Interaction risk (constrains the plan):** `goal_complete` is central to #16's soft-stop machinery — `restrictToGoalComplete`, the summary turn, and the `onSubagentComplete` nil-out on completion. The schema/handler change must preserve that behavior; the plan treats the loop-control paths as a fixed constraint, not a blank slate.
- **Stop-before wired to approvals.** `stopBefore` boundaries integrate with Iris's existing approval system (`requestApproval` / Vibecop / the pending-approval queue): an action matching a stop-before boundary requires explicit approval, even inside an autonomous goal run. To be precise about what this is: a boundary *denylist* enforced at the action, reusing the existing approval machinery — **not** the field docs' full "scoped authorizations" (a per-grant scope that expires at the next milestone). That finer model is a later concern; don't conflate the two.
- **Amending the contract requires a rationale (the change-log's teeth).** A locked contract has exactly one change path, and it carries a rationale — there is no silent-edit route. For the model: a dedicated `amend_goal_contract(target, change, rationale)` tool (the model's only handle on locked criteria). For the human: the panel's edit-with-rationale action. Both append a `ContractChange` and surface it. The struct's mutation helpers reject a post-lock criteria change with an empty rationale (§4 invariant), so the discipline is enforced in code, not prose.
- **Migration hazard (must be enumerated in the plan).** Switching the loop's active-goal gate from `activeGoal != nil` to `goalContract?.isLocked` touches every site that reads `activeGoal`: loop detection, the iteration cap, the auto-reprompt, and soft-stop (#16). Missing one silently regresses the loop-control work. The plan enumerates and converts all of them, with a gate test each.

## 7. The larger arc (roadmap — context only, not built here)

This slice is **A**. The rest, in dependency order, each its own spec:
- **C — Impartial drift evaluator (#9 core):** a fresh-context evaluator grades the work against the *locked* contract (executable criteria via their `check`; qualitative via LLM-judge on the concrete description; humanJudged surfaced, never auto-graded). The trusted gate. Next after A.
- **B — Inner/outer loop semantics (#13):** formalize outer (main agent holds the contract, delegates) vs inner (subagent builds a bounded unit, reports a structured result), and the context boundary between them. **Checkpoints / a milestone ladder live here** — ordered stop points that sequence A's flat criteria into human-re-engagement points, so a long goal runs *between* checkpoints instead of to a single terminal `goal_complete`.
- **D — Deterministic done-gates:** block `goal_complete` unless the evaluator (C) passes or a `n/a — <reason>` escape hatch is stated. Gates check artifacts, not intentions.
- **E — The ratchet:** per-goal learnings → memory → promoted rules → (if re-violated) hooks.
- **F — Ground-truth progress view:** a panel that reads the real contract + evidence, so the human steers by exception.

## 8. Persistence & UI

- Contract persists on the `Conversation` (Iris already persists goals via `Codable`; `goalContract` decodes with `decodeIfPresent` for backwards compatibility).
- A **contract panel**: renders criteria with kind badges, out-of-scope, stop-before, assumptions; fully editable while `draft`; an **Approve** action that locks. During a locked run, a compact chip/panel shows the oracle you're being held to and any change-log entries.
- **The completion report is visibly marked unverified.** When `goal_complete` reports per-criterion status, the panel renders each status as *self-reported / unverified* — never a green "verified" check — until slice C exists to grade it independently. A must not present a self-report as a passed gate; that is precisely the self-grading-drifts-into-passing failure the field docs warn about, and the UI is where a user would be misled.
- **Scope of the contract is per-goal, not a persistent project oracle.** It lives on the `Conversation` and ends with the goal, so successive `/goal`s on the same project don't inherit criteria. Conscious v1 tradeoff; the deferred `docs/SUCCESS-CRITERIA.md` export below is the eventual path to a persistent, cross-goal oracle.
- Exporting a locked contract to a workspace `docs/SUCCESS-CRITERIA.md` when a workspace is active is a natural later add — **deferred**.

## 9. Error handling & edge cases

- **`/goal` with no text** → Iris asks for the objective (can't draft from nothing).
- **Draft the user rejects wholesale** → discard; no goal set; normal chat resumes.
- **Empty/allHumanJudged criteria** → allowed (a purely taste-driven goal); the loop simply has no machine-checkable "done" and leans on the human. Surfaced honestly.
- **Upgrade migration** → a pre-existing `activeGoal` string with no `goalContract` becomes a locked contract with one `qualitative` criterion = the old text, so running goals aren't dropped by the schema change.

## 10. Testing

**Pure / unit-testable:**
- `GoalContract`/`Criterion` encode-decode round-trip; `decodeIfPresent` backwards compat; the migration (old `activeGoal` string → locked single-criterion contract).
- Lock transition; the change-log invariant (post-lock criteria edit without a rationale is rejected).
- The amend path: `amend_goal_contract` with a rationale appends a `ContractChange` and is visible; without a rationale it is rejected.
- `goal_complete`'s new schema carries per-criterion status.
- Loop gate reads `goalContract?.isLocked` (not `activeGoal != nil`) — **and every former `activeGoal`-gated path (loop detection, iteration cap, auto-reprompt, soft-stop) is converted, each with its own gate test**, so #16's behavior is preserved.

**Model-driven / GUI-verified by the user:** the drafting quality, the narrow clarify questions, the panel edit→lock UX, and that the locked contract actually appears in the loop's context.
