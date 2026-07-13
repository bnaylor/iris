---
title: Dynamic Model Tiers & Auto-Selection
type: spec
status: draft
---

# Dynamic Model Tiers & Auto-Selection

## Objective
Introduce "Easy", "Medium", and "Hard" model settings. The primary Iris agent will default to the Medium model for its conversational loop but will dynamically spawn subagents on different tiers based on task complexity to optimize for speed, cost, and reasoning capability.

## Available Models (Defaults)
*   **Easy:** `gemini-3.1-flash-lite` (Optimized for high-volume, cost/latency-sensitive workloads)
*   **Medium (Primary Agent Default):** `gemini-3.5-flash` (Mainstream model, Pro-level coding at Flash speeds)
*   **Hard:** `gemini-3.1-pro-preview` (Advanced reasoning, complex problem-solving)

*(Fallback/Legacy options like `gemini-2.5-flash` will also be available in the dropdowns).*

## Architecture

### 1. `ConfigManager` & `SettingsView`
Replace the single `geminiModel` with three distinct properties in `ConfigManager`:
*   `modelEasy`
*   `modelMedium`
*   `modelHard`
`SettingsView` will display three separate pickers under the "LLM Providers" section. The primary agent will route its requests using `modelMedium`.

### 2. Subagent Engine Updates
*   **`IrisEngine`**: Update the engine to hold a `modelTier` property (enum: `.easy`, `.medium`, `.hard`). When invoking the `LLMClient`, the client will select the specific model string from `ConfigManager` based on this tier.
*   **`SubagentManager`**: The `runSubagent` method will be updated to accept an `effort` parameter and pass it to the child `IrisEngine`.

### 3. Tool Updates (`invoke_subagent`)
Add a new `effort` parameter to the `invoke_subagent` schema:
*   `type: STRING`
*   `enum: ["easy", "medium", "hard"]`
*   `description: "The reasoning effort required for this task. Easy = simple lookups, Medium = standard tasks, Hard = complex problem solving."`

### 4. Delegation Directives (System Prompt)
Update the `superpowersInstruction` or `skills` in `iris.swift` to explicitly instruct Iris to use the `effort` parameter when delegating:
*   "You run on a Medium tier model. For deep, complex reasoning, invoke a Hard subagent. For trivial repetitive tasks, invoke an Easy subagent."
