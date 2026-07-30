# Goal Drift Evaluator (slice C) — Design

* **Issues**: [#9](https://github.com/bnaylor/iris/issues/9) (dynamic gates + impartial evaluator) — the evaluator half. Builds on merged **slice A** ([2026-07-28-goal-contract.md](2026-07-28-goal-contract.md)).
* **Date**: 2026-07-29
* **Status**: Approved

## 1. Overview

Slice A made a goal into a locked **contract** and had `goal_complete` emit a per-criterion **self-report** — which the UI is forced to label UNVERIFIED, because the same context that did the work graded itself. Slice C adds the missing half: a **fresh-context evaluator** that independently grades the finished work against the locked contract and produces a *trusted* per-criterion verdict, shown side-by-side with the self-report so the gap between claimed and verified is visible.

## 2. Scope of this slice (C: the impartial drift evaluator)

C **produces + persists + displays** a trusted grade. It does **not** block completion or re-engage the loop.

**Honesty boundary (stated up front):** the grade is trustworthy *because* it comes from a context that curated no evidence and never saw the working transcript — adversarial verification. The evaluator must be able to answer `cannot_verify` and must never fabricate a pass. The value of the slice is surfacing **drift** (self-report claims `met`, grader finds `not_met`), not preventing it.

**Explicitly deferred (deliberate, not silent omissions):**
- **The hard gate, soft-retry, and `n/a — <reason>` escape hatch → slice D.** A failing grade in C does not stop `goal_complete`; it is advisory. Using the grade to block completion or re-prompt the agent to retry requires the retry cap + escape hatch that define D — building retry without them ships *trapped goals* (a grader that keeps failing a criterion the agent can't satisfy, especially `humanJudged`).
- **Interactive `humanJudged` verdicts → slice D.** In C, `humanJudged` criteria are surfaced as "your call," never auto-graded; wiring a human accept/reject that feeds a gate is D's concern.
- **Read-only sandbox mount for the grader → v2 hardening.** C strips mutation tools structurally and routes shell through the existing sandbox/approval path; a stricter read-only workspace mount is a later hardening.
- **Ground-truth progress panel → slice F.** Grading **subagent** completions — out of scope (subagents get a bare `setGoal` string, not a contract).

## 3. Architecture

### 3.1 A new principal

Add `Principal.evaluator` alongside `.main` and `.subagent`. The engine already branches on `principal` for toolset assembly, sandbox policy, and (new here) the Vibecop prompt layer, so `.evaluator` is the seam that grants the restricted toolset + grader Vibecop layer + grader system prompt without altering main/subagent behavior.

### 3.2 Trigger

In the `goal_complete` handler, **only when `principal == .main` and a `goalContract` exists** (subagents have no contract → never graded; the grader itself terminates via `submit_evaluation`, not `goal_complete`, so there is no recursion). The handler today does: record self-report → `clearGoal` (nils `goalContract`) → callbacks → summary. C inserts, *before* `clearGoal`:

1. Write `lastGoalEvaluation = .verifying` with the contract's criteria **captured** (this snapshot — criterion id/text/kind/check — is what the grader grades against, so `clearGoal` niling `goalContract` is irrelevant afterward).
2. Kick an **async grading run** (does not block `goal_complete`'s return or the loop).

`goal_complete` returns immediately; the verdict fills in when the run finishes.

### 3.3 The grading run

A fresh conversation + fresh `IrisEngine(principal: .evaluator)` — same isolation as a subagent, so it never sees the working transcript. It is given the contract snapshot + workspace path, gathers its own evidence with a read-only toolset (§4), and **terminates by calling `submit_evaluation`** (its analog of `goal_complete`), which writes the structured verdict back to the originating conversation. A per-run iteration cap prevents a confused grader from running forever; if the cap is hit or the run errors, the evaluation is marked `.failed` and any ungraded criteria are `cannot_verify`.

### 3.4 Alignment

Slice A's `Criterion`s carry stable UUIDs. The grader grades those (verdicts keyed by `criterion_id`), so the UI lines up **contract criterion → grader verdict** exactly. Slice A's self-report is text-keyed, so it is matched **best-effort by text** against the contract criteria for the side-by-side view.

## 4. The grader's contract

### 4.1 Toolset (`.evaluator`)

The engine's tool assembly, when `principal == .evaluator`, builds a minimal set: `read_file`, directory listing, `run_command` (routed through the grader Vibecop layer, §5), and the terminal `submit_evaluation`. **Absent by construction**: every mutation/goal tool — `write_file`, `create_skill`/`update_skill`, `goal_complete`, `propose_goal_contract`, `amend_goal_contract`, `invoke_subagent`, `set_workspace`, memory writes. Grading-can't-become-editing is structural, not merely sandboxed.

### 4.2 Grader system prompt

Adversarial and skeptical: *your job is to independently determine whether the finished work satisfies each criterion of this locked contract, using your own inspection — you did not do the work and have no stake in it passing.* Honesty invariant: return `cannot_verify` when you genuinely cannot determine a criterion; **never fabricate a pass**. Grade only the contract's criteria — do not invent new ones or grade scope creep.

### 4.3 `submit_evaluation` (terminal tool)

Args: `evaluations: [{criterion_id, verdict: met|not_met|cannot_verify, evidence}]` — an ARRAY of OBJECT (with proper `items`, now that `Schema` supports it). Calling it writes the verdict to the originating conversation and ends the run.

**Reconciliation against the full criteria list** (the grader may omit criteria): for each contract criterion, if the grader supplied a verdict, use it; else if the criterion's kind is `humanJudged`, record `humanPending` (the grader is instructed not to grade these); else record `cannot_verify`. So every criterion always carries a verdict, and a `humanJudged` criterion never collapses to `cannot_verify`.

### 4.4 Per-criterion mechanics

- **executable** → the grader runs the `check` command; exit `0` = `met`, nonzero = `not_met`, couldn't run it = `cannot_verify`. Evidence = command + exit code + output snippet. Near-deterministic — the exit code is ground truth; the model reports it faithfully.
- **qualitative** → the grader inspects artifacts (diff, files, running the thing) against the concrete "done looks like X" description → `met`/`not_met`/`cannot_verify` + a concrete evidence pointer (`file:line`, output).
- **humanJudged** → the grader is instructed **not** to grade these; they are carried into the verdict as `humanPending` ("your call"), surfaced in the UI, never auto-graded.

## 5. Vibecop grader layer

`VibecopService.evaluateAction` gains a caller-role parameter (keyed off `principal`) plus the contract's declared `check` commands. For the `.evaluator` caller it composes a stricter layer on top of the existing paranoid base + per-workspace `.iris/vibecop.md`:

> The caller is an evaluator grading finished work against a fixed contract. Its only legitimate actions are reading files and running these declared check commands: [the contract's `check`s]. Anything that writes, installs, deletes, reaches the network, or runs a command outside that set is out of role — escalate or deny.

Passing the `check` allowlist lets Vibecop distinguish "running the declared check" (allow) from "arbitrary command" (suspect) rather than guessing. The workspace guardian still applies underneath; the grader layer only tightens.

## 6. Data model & persistence

- **`CriterionVerdict`**: `criterionId: UUID`, `criterionText: String`, `kind: CriterionKind`, `verdict: met | notMet | cannotVerify | humanPending`, `evidence: String`, `method: check | judge | human`.
- **`GoalEvaluation`**: `status: verifying | graded | failed`, `criteria: [CriterionVerdict]`, `startedAt: Date`, `completedAt: Date?`.
- **On `Conversation`**: new `lastGoalEvaluation: GoalEvaluation?` — Codable, added to `CodingKeys`, decoded with `decodeIfPresent` (same pattern as `goalContract`/`lastGoalCompletionReport`), so existing conversations decode to `nil`.
- **Snapshot**: written `.verifying` at `goal_complete` before `clearGoal`, with the contract's criteria captured; the async grader flips it to `.graded` (or `.failed`).
- **Lifecycle**: the evaluation is the completion chip's partner. The ✕ dismiss clears **both** `lastGoalCompletionReport` and `lastGoalEvaluation`; starting a new `/goal` (`setDraftContract`) clears both.

## 7. UI (the drift-reveal chip)

The existing completion chip becomes the drift view, with `lastGoalEvaluation.criteria` as the spine. Per criterion, a row shows: **criterion text + kind badge · self-reported verdict · grader verdict + evidence**, with a **⚠ drift** flag on any row where the two disagree.

Honesty styling (carried from A): the **self-report column stays neutral and never shows a green check** (still an unverified claim); the **grader column earns real color** — green `met`, red `not_met`, neutral `cannot_verify`, "your call" for `humanPending`. The per-column styling *is* the drift signal: agent claimed met (neutral) vs. grader says not_met (red).

While `status == .verifying`, the grader column shows a "verifying…" state and fills in when the async run lands. The ✕ dismiss clears report + evaluation.

## 8. Testing

- `GoalEvaluation`/`CriterionVerdict` Codable round-trip + migration (`decodeIfPresent` → `nil` for legacy conversations).
- `submit_evaluation` parsing (`JSONValue → [CriterionVerdict]`): unknown verdict → `cannotVerify`; omitted contract criteria → `cannotVerify`.
- The `.evaluator` assembled toolset **excludes** every mutation/goal tool and **includes** `submit_evaluation` + read/run (assert over the assembled list, reusing the `arrayItemsViolations`-style assembly-exercising path).
- The grader Vibecop prompt layer is selected for `.evaluator` (caller-role branch) and carries the check allowlist.
- `executable` mapping: trivial checks (`true` / `false` / `exit 1`) → `met` / `not_met`.
- Behavioral: `goal_complete` on a locked contract (principal `.main`) writes `lastGoalEvaluation = .verifying` and kicks the grader; a scripted evaluator engine (`ScriptedLLMClient`) calling `submit_evaluation` fills verdicts → `.graded`.
- Regression: slice A + #16 suites stay green (`goal_complete` still clears the goal, self-report still recorded).

## 9. The larger arc (where C sits)

C is the impartial evaluator (#9 core). Next in dependency order is **D — deterministic done-gates**: consume C's verdict two ways — a **soft retry** re-prompt (the agent is told which criteria are `not_met` + evidence, and works before finishing) and a **hard gate** (`goal_complete` refused unless graded-pass or a stated `n/a — <reason>`), both guarded by a retry cap + the escape hatch, plus interactive `humanJudged` verdicts. C is what makes D possible and safe to build: it produces the structured, trustworthy signal D consumes. (Slice **B** — inner/outer loop + checkpoints — and **F** — ground-truth progress panel — remain independent, per the slice-A roadmap §7.)
