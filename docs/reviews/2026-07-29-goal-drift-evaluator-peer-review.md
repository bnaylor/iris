# Peer Review: Goal Drift Evaluator (Slice C, #9)

* **Target PR:** [#53](https://github.com/bnaylor/iris/pull/53) - `feat(eval): Goal Drift Evaluator — fresh-context grader that verifies goal completion`
* **Author:** Brian Naylor / Claude Code
* **Reviewer:** Clomp
* **Date:** 2026-07-29
* **Status:** Approved

---

## Executive Summary

PR #53 implements **Slice C** of the Goal Contract arc ([Issue #9](https://github.com/bnaylor/iris/issues/9)). It introduces an independent, fresh-context **Goal Drift Evaluator** that runs upon `goal_complete` execution for main agent conversations with a locked `GoalContract`.

The evaluator runs detached (non-blocking) in a fresh subagent conversation (`Principal.evaluator`), without access to the main conversation's working transcript or tool history. It executes contract check commands, LLM-judges qualitative criteria, preserves human-judged criteria as pending, and emits a structured `GoalEvaluation` that renders side-by-side with the agent's self-report in a two-column drift view.

---

## Architectural & Security Verification

1. **Adversarial Isolation:**
   - The evaluator executes in a separate subagent conversation (`isSubagent: true`, titled "Evaluator") with `Principal.evaluator`.
   - It receives only the locked `GoalContract` and workspace path — it never sees the main working transcript.

2. **Mutation-Free Toolset Construction (`EvaluatorToolset.swift`):**
   - Hard-limits available tools via `EvaluatorToolset.restrict` to exactly `{read_file, run_command, submit_evaluation}`.
   - All state-modifying tools (`write_file`, `create_skill`, `goal_complete`, `invoke_subagent`, `propose_goal_contract`, etc.) are stripped by construction.

3. **Vibecop Grader Protection (`VibecopService.swift`):**
   - Implements `callerRole: .evaluator` layer in `VibecopService`.
   - Threads the contract's declared `check` commands into an allow-list, approving reads and declared check commands while blocking/denying writes, installs, or network access.

4. **Honest Verdict Reconciliation (`GoalEvaluationParsing.swift`):**
   - Omitted criteria fall back to `cannot_verify` rather than an assumed pass.
   - `humanJudged` criteria are preserved as `human_pending` ("your call") and are never auto-graded.
   - Any grader attempt to claim `human_pending` on a non-human criterion is coerced to `cannot_verify`.

5. **Drift-Revealing UI (`GoalContractPanel.swift` & `ChatView.swift`):**
   - Renders a two-column layout comparing agent self-reports against grader verdicts.
   - Automatically surfaces a `⚠ drift` indicator when the agent claims `met` but the grader determines `not_met` or `cannot_verify`.

---

## Test Coverage Analysis

The PR adds 6 comprehensive unit test suites:
- `EvaluatorToolsetTests`: Verifies tool restriction and array parameter schema compatibility.
- `GoalEvaluationParsingTests`: Verifies verdict mapping, omission reconciliation, and `humanJudged` handling.
- `GoalEvaluationTests`: Verifies Codable roundtrips and backward-compatibility defaults (`nil` evaluation for legacy records).
- `GoalEvaluatorTriggerTests`: Verifies snapshot creation and evaluator subagent dispatch upon `goal_complete`.
- `SubmitEvaluationHandlerTests`: Verifies callback dispatch and evaluator loop termination.
- `VibecopEvaluatorLayerTests`: Verifies prompt construction for the evaluator role.

---

## Conclusion & Verdict

**APPROVED.** The design achieves complete adversarial isolation, zero mutation risk, and high-signal drift reporting without blocking goal completion. Ready to merge.
