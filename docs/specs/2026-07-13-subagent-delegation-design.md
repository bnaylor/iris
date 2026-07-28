---
title: Subagent Delegation & Role-Constrained Execution
type: spec
status: draft
---

# Subagent Delegation & Role-Constrained Execution

## Objective
Enhance Iris with the ability to recursively spawn isolated, role-constrained subagents to parallelize tasks and improve execution quality through crisp, specialized context.

## Architecture

### 1. The `invoke_subagent` Tool
A new tool exposed to the primary Iris agent.
- **Parameters:**
  - `role`: The constrained persona for the subagent (e.g., `researcher`, `engineer`, `code_reviewer`, `security_auditor`).
  - `task`: The specific goal or prompt for the subagent to execute.
- **Behavior:** This tool will block the parent agent's execution until the subagent completes its task and returns a summary. (Alternatively, it could return a job ID for asynchronous checking, but synchronous blocking is simpler for a V1).

### 2. Role-Specific System Prompts
Instead of the massive, generic `soul` prompt used by the primary agent, subagents will receive highly tailored system instructions based on their `role`. 
- **Code Reviewer:** Focuses purely on finding bugs, architectural flaws, and style issues without writing new feature code.
- **Security Auditor:** Focuses strictly on vulnerabilities (e.g., injection, bounds checking).
- **Researcher:** Focuses on using the `search_web` and `read_file` tools to gather context without mutating state.
- **Engineer:** Focuses on isolated TDD execution for a specific component.

### 3. Lifecycle (`SubagentManager.swift`)
- When `invoke_subagent` is called, `SubagentManager` instantiates a new `AppState` conversation and a fresh `IrisEngine`.
- The engine's `systemPrompt` is overridden with the role-specific prompt.
- The `task` is passed as the first user input.
- The subagent operates autonomously (running tools, sandboxed commands, etc.) until it calls `goal_complete` with a `summary`.
- The `summary` is then returned directly to the parent agent as the result of the `invoke_subagent` tool call.

### 4. Delegation Directives
The primary Iris agent's system prompt (`superpowersInstruction`) will be updated to explicitly encourage delegating tasks using this tool. For example: "If you write a complex feature, invoke a `code_reviewer` subagent to audit it before declaring it complete."

## Trade-offs
- **Token Usage:** Spawning subagents inherently multiplies token usage. We accept this trade-off for higher quality and isolated context.
- **Synchronous vs Async:** In V1, `invoke_subagent` will be synchronous (parent waits for child). In the future, this can be made async so the parent can spawn multiple subagents in parallel.
