---
type: plan
title: Sandbox UI Approval Banners Polish
description: Priorities and fixes for global approval banner rendering, subagent tab switching issues, and queue depth indicators.
tags: [sandbox, ui, feedback, approvals]
timestamp: 2026-07-26T00:15:00Z
---

# Sandbox UI Approval Banners Polish

During manual verification of Phase 2a (Test D / Overhaul), several UI rendering anomalies were observed regarding the `ApprovalBannerView` and subagent conversation focus:

## Observed Behaviors (Feedback Logs)
1. **Conversation Binding Mismatch:** The approval banners did not automatically display globally in the active main conversation's view. The user had to manually switch to the hidden/subagent conversation tabs to see the respective approval banners.
2. **Missing Queue Depth Badge:** The `"N more pending"` queue depth indicator did not render on screen as expected when multiple requests were stacked.
3. **Banner Crossover:** An `engineer` subagent's approval request banner was displayed while viewing the `auditor`'s conversation window, indicating that the banner rendering is not strictly conversation-bound or globally aligned.

## Root Cause Analysis
- **Local View State vs Global Overlay:** `ApprovalBannerView` is currently placed inside `ChatView.swift`'s `detail:` block under `VStack(spacing: 0)` which is bound to `state.activeConversationIndex`. If the UI state is not actively focused on the conversation initiating the request, or if SwiftUI's view hierarchy unmounts/hides sections of the active conversation, the banner is hidden.
- **Queue Count Binding:** SwiftUI `@Observable` might not be triggering redraws for `state.pendingApprovals.count` if the collection mutation happens inside `withCheckedContinuation` without explicit publisher triggers or if the array changes are masked during thread-hopping.

## Plan of Action (Next Phase)

### Task 1: Decouple Banner from Conversation Detail View
Move `ApprovalBannerView` out of the conversation `detail:` split view and place it as a **true global overlay** on the outermost SwiftUI `ZStack` in `ChatView.swift` (spanning across the sidebar and the detail view). This guarantees:
- Banners appear instantly on screen regardless of which conversation is currently active.
- Background subagent requests are never missed because the user does not have to switch tabs.

### Task 2: Strict Origin/Conversation Context Matching
- Update `ApprovalBannerView` to strictly check if the enqueued request is bound to the currently focused `selectedConversationId` (if we want conversation-bound banners), OR ensure it clearly displays a prominent header/badge identifying the subagent's role (e.g. `[Subagent: Security Auditor]`) when shown globally.

### Task 3: Verify and Fix `@Observable` Queue Depth Redraws
- Verify that `pendingApprovals` updates trigger SwiftUI redraws properly. Consider wrapping mutations to `pendingApprovals` in an explicit `objectWillChange.send()` or dispatching array changes on `MainActor.run { self.pendingApprovals.append(...) }` to guarantee that SwiftUI's reactive engine registers the count change and displays the `"N more pending"` badge.

