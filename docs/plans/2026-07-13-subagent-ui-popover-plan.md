---
title: Subagent UI Popover Implementation Plan
type: plan
status: draft
---

# Implementation Plan: Subagent UI Popover

## Step 1: Model Updates
- In `Models.swift` (or `AppState.swift`), define the `ActiveSubagent` struct:
  - `id: UUID`
  - `role: String`
  - `startTime: Date`
  - `status: String`

## Step 2: AppState Updates
- Add `var activeSubagents: [ActiveSubagent] = []` to `AppState`.
- Add thread-safe helper functions:
  - `func registerSubagent(id: UUID, role: String)`
  - `func removeSubagent(id: UUID)`
  - `func updateSubagentStatus(id: UUID, status: String)`

## Step 3: SubagentManager & Engine Lifecycle
- In `SubagentManager.swift`, call `appState.registerSubagent(id: subagentId, role: role)` before starting the engine.
- Call `appState.removeSubagent(id: subagentId)` when the subagent completes.
- In `iris.swift` (`IrisEngine`), before generating content, call `appState.updateSubagentStatus(id: conversationId, status: "Thinking...")`. After generating, call `appState.updateSubagentStatus(id: conversationId, status: "Executing...")`.

## Step 4: UI Development (`SubagentPopoverView.swift`)
- Create a new SwiftUI View `SubagentPopoverView`.
- Accept `@Bindable var appState: AppState`.
- Iterate over `appState.activeSubagents`.
- For each item, display a `VStack` inside an `HStack` with an animated `ProgressView`, the role, the current status, and a dynamic elapsed time indicator using `Text(timerInterval:)` or a custom timer.

## Step 5: ChatView Integration
- In `ChatView.swift`, find the `toolbar` block.
- Add a toolbar item on the trailing edge (e.g., `Image(systemName: "cpu")`).
- Add a `.popover(isPresented: $showSubagents)` to display `SubagentPopoverView`.
- Show a badge overlay on the icon if `appState.activeSubagents.count > 0`.

## Step 6: Test & Build
- Verify UI renders correctly without crashes.
- Verify subagents populate the list when spawned and disappear when finished.
