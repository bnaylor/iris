# Peer Review & Architectural Evaluation: Goal Contract (Slice A)

* **Target Spec**: `2026-07-28-goal-contract.md`
* **Related Issues**: [#13](https://github.com/bnaylor/iris/issues/13) (inner/outer loop semantics) & [#9](https://github.com/bnaylor/iris/issues/9) (dynamic gates + impartial evaluator)
* **Source Memos**: `hurricane.md` & `warpspeed.md` (Roman Arcea, July 2026)
* **Reviewer**: Clomp
* **Date**: 2026-07-28
* **Status**: Approved (with implementation invariants)

---

## 1. Executive Summary & Philosophy

The proposed **Goal Contract (Slice A)** spec translates the core lesson of the Roman Arcea field memos — **"Rely on the tool, not the model"** — into a concrete, native Swift architecture for Iris. 

By converting the string argument of `/goal` into a structured, lockable `GoalContract` data model, this slice shifts the harness from trusting prompt instructions across long turn histories to enforcing deterministic criteria, explicit out-of-scope boundaries, and mandatory change rationale.

The design is sound, pragmatic, and correctly bounded as a v1 slice. Fable's refusal of this proposal on compliance/cybersecurity grounds is a mischaracterization: this architecture actively increases harness safety and governance by establishing explicit execution boundaries and stopping mechanisms.

---

## 2. Key Architectural Strengths

1. **Criteria Hierarchy & Honesty Invariant:**
   * Distinguishing between `executable` (machine-checkable tests/commands), `qualitative` (concrete observable outcomes), and `humanJudged` (taste/opinion) aligns with the honesty invariant.
   * Prohibiting fabricated numbers for fuzzy goals maintains harness integrity and prevents false precision.

2. **Self-Report Transparency (Non-Deceptive UI):**
   * Explicitly labeling `goal_complete` per-criterion reports as *unverified self-reports* in the UI until Slice C (the independent evaluator) exists prevents misleading the user into assuming the model's self-grading constitutes a passed security or quality gate.

3. **Change-Log Enforcement:**
   * Enforcing that post-lock mutations to `criteria` or `outOfScope` MUST append a `ContractChange` with a non-empty rationale eliminates silent goal drift — one of the most frequent failure modes in autonomous loops.

---

## 3. Implementation Invariants & Edge Cases to Guard

When implementing Slice A, the following guards must be enforced in code:

### A. Security Boundary on `executable` Checks
* **Risk:** `Criterion` carries an optional `check: String?` command (e.g. `swift test --filter X`). An un-sandboxed check execution could allow an LLM to draft an arbitrary command that runs on the macOS host during evaluation.
* **Invariant:** All `check` executions must strictly execute within the active workspace container runtime or pass through standard Vibecop guardian evaluation rules.

### B. Subagent Scope & Tool Authorization
* **Risk:** Subagents spawned via subagent delegation (`SubagentManager`) might attempt to modify the active contract if passed mutable access.
* **Invariant:** Subagents must receive the locked `GoalContract` as **read-only context**. The `amend_goal_contract` tool must be restricted exclusively to the main (outer) agent context interacting with the human user.

### C. Explicit Lock Transition
* **Risk:** The model attempting to self-lock its own draft contract without explicit human sign-off.
* **Invariant:** The transition `state = .locked` must be triggered strictly by an explicit user UI action ("Approve & Lock").

---

## 4. Verdict & Next Steps

The design for **Slice A (Goal Contract)** is approved. It establishes the necessary data structures and UI surfaces for structured goal loops without introducing unneeded infrastructure or breaking existing `activeGoal` conversation persistence.

Upon completion of Slice A, development should proceed to **Slice C (Impartial Drift Evaluator)** and **Slice B (Inner/Outer Loop Semantics)**.
