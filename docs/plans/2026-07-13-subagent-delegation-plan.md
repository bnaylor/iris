---
title: Subagent Delegation Implementation Plan
type: plan
status: draft
---

# Implementation Plan: Subagent Delegation

## Goal
Implement the `invoke_subagent` tool, `SubagentManager`, and update the primary `IrisEngine` prompt to enable autonomous, role-constrained parallel delegation.

## Steps

### Step 1: SubagentManager & Core Scaffolding
- [ ] Create `Sources/iris/SubagentManager.swift`.
- [ ] Implement `runSubagent(role: String, task: String) async -> String` which will:
  - Create a new `conversationId`.
  - Instantiate a new `AppState` (or use the shared one with a new conversation).
  - Construct a highly constrained `systemPrompt` based on the requested `role` (`code_reviewer`, `security_auditor`, `researcher`, `engineer`).
  - Send the `task` as a system/user event.
  - Wait for the subagent to call `goal_complete` (we'll need a mechanism to intercept or capture the `summary` from `goal_complete`).

### Step 2: The `invoke_subagent` Tool
- [ ] Modify `Sources/iris/ToolExecutor.swift`.
- [ ] Add the `invoke_subagent` `FunctionDeclaration` with `role` and `task` parameters.
- [ ] Route the execution to `await SubagentManager.shared.runSubagent(role: role, task: task)`.

### Step 3: Intercepting `goal_complete`
- [ ] Update `iris.swift` or `ToolExecutor.swift` to capture the output of `goal_complete`.
- [ ] When a subagent calls `goal_complete`, we need to return that summary to the caller (`SubagentManager`) instead of just logging it. We can add an `onGoalComplete` callback to `AppState` or `SubagentManager`.

### Step 4: TDD & Mocking
- [ ] Create `Tests/irisTests/SubagentManagerTests.swift`.
- [ ] Verify that `invoke_subagent` correctly wires up the custom prompt and captures the `goal_complete` result.

### Step 5: Update the Delegation Directives
- [ ] Open `Sources/iris/iris.swift` and append the subagent delegation heuristics to `skills` or `superpowersInstruction`.
- [ ] Emphasize that Iris should use this to parallelize context or get focused reviews on its own code.

### Step 6: Refactor & Clean Up
- [ ] Ensure thread safety when manipulating `AppState` for multiple concurrent subagents.
- [ ] Test the full loop end-to-end.
