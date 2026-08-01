# Goal Checkpoint Ladder (slice B1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Sequence a goal contract's flat criteria into an ordered partition of milestones, each ending in a checkpoint that hard-stops the loop, grades cumulatively via the slice-C evaluator, and re-engages the human.

**Architecture:** Add milestone/ladder state to `GoalContract` (all `decodeIfPresent`-defaulted). A new `reach_checkpoint` tool — offered only when a ladder is active and the current milestone isn't the last — pauses the loop (`checkpointStatus = .pausedForReview`, `activeGoal` left set), awaits a `GoalEvaluator` run over a projected cumulative sub-contract, and surfaces the verdict. Resume is human-driven from `GoalContractPanel`: advance to the next milestone or send the agent back. `goal_complete`, `SubagentManager`, and #16's soft-stop machinery are untouched.

**Tech Stack:** Swift 5.9+, Swift Testing (`import Testing`, `@Suite`/`@Test`/`#expect`), SwiftUI (AppKit-hosted). Tests drive the engine with `ScriptedLLMClient`.

## Global Constraints

- Spec: `docs/specs/2026-08-01-goal-checkpoint-ladder.md`. Every task traces to a section there.
- **`goal_complete` semantics must not change** — it stays the sole terminal path (clears the goal, self-reports, fires the background C grade + skill-check reflection). `reach_checkpoint` is a *parallel* intermediate signal, never an overload of `goal_complete`.
- **The loop gate stays `activeGoal != nil`.** A checkpoint pause leaves `activeGoal` set and suppresses the auto-reprompt via `checkpointStatus`; it never clears the goal.
- **`GoalEvaluator.evaluate(...)` is reused unmodified.** Checkpoint grading only constructs a projected sub-contract to hand it.
- **No auto-gating.** A `not_met` checkpoint verdict is presented, never enforced. Automatic block/retry is deferred to slice D.
- **Backwards compatibility:** new `GoalContract` fields decode with `decodeIfPresent`/defaults; a legacy contract decodes to an empty ladder (`hasLadder == false`) and behaves exactly as today.
- New fields are `Codable, Equatable, Sendable` to match the existing `GoalContract` conformances.
- Ladder helpers must not crash on malformed data — normalize on decode (fold unassigned criteria into an implicit final milestone; clamp `currentMilestone`).

---

### Task 1: Ladder data model on `GoalContract`

**Files:**
- Modify: `Sources/iris/GoalContract.swift`
- Test: `Tests/irisTests/GoalContractLadderTests.swift` (create)

**Interfaces:**
- Consumes: existing `GoalContract`, `Criterion`, `CriterionKind`, `ContractState`.
- Produces:
  - `struct Milestone: Codable, Identifiable, Equatable, Sendable { var id = UUID(); var title: String; var criterionIds: [UUID] }`
  - `enum CheckpointStatus: String, Codable, Sendable, Equatable { case running, pausedForReview }`
  - `GoalContract` fields: `var milestones: [Milestone] = []`, `var currentMilestone: Int = 0`, `var checkpointStatus: CheckpointStatus = .running`
  - `var hasLadder: Bool` (`!milestones.isEmpty`)
  - `var isFinalMilestone: Bool` (`currentMilestone >= milestones.count - 1`)
  - `func currentMilestoneCriteria() -> [Criterion]`
  - `func projectedContract(throughMilestone n: Int) -> GoalContract` (locked copy; `criteria` = cumulative through `n`; `milestones` emptied)
  - `func ladderIsValidPartition() -> Bool` (disjoint + covering; empty ladder is valid)
  - `func normalizedLadder() -> GoalContract` (drop stray ids, fold unassigned into implicit final milestone, drop empty milestones, clamp `currentMilestone`)

- [ ] **Step 1: Write the failing tests**

Create `Tests/irisTests/GoalContractLadderTests.swift`:

```swift
import Testing
import Foundation
@testable import iris

@Suite("GoalContract ladder")
struct GoalContractLadderTests {
    private func laddered() -> GoalContract {
        let a = Criterion(text: "build green", kind: .executable, check: "swift build")
        let b = Criterion(text: "tests pass", kind: .executable, check: "swift test")
        let c = Criterion(text: "docs updated", kind: .qualitative, check: nil)
        var contract = GoalContract(objective: "Ship it", criteria: [a, b, c])
        contract.milestones = [
            Milestone(title: "Compile", criterionIds: [a.id]),
            Milestone(title: "Verify", criterionIds: [b.id, c.id]),
        ]
        return contract
    }

    @Test("hasLadder and isFinalMilestone reflect the ladder")
    func flags() {
        var c = laddered()
        #expect(c.hasLadder)
        #expect(!c.isFinalMilestone)          // currentMilestone == 0, two milestones
        c.currentMilestone = 1
        #expect(c.isFinalMilestone)
        let empty = GoalContract(objective: "x", criteria: [])
        #expect(!empty.hasLadder)
    }

    @Test("currentMilestoneCriteria returns only the current milestone's criteria")
    func currentSlice() {
        let c = laddered()
        #expect(c.currentMilestoneCriteria().map(\.text) == ["build green"])
    }

    @Test("projectedContract is cumulative through N, locked, and de-laddered")
    func projection() {
        let c = laddered()
        let p0 = c.projectedContract(throughMilestone: 0)
        #expect(p0.criteria.map(\.text) == ["build green"])
        #expect(p0.milestones.isEmpty)
        #expect(p0.isLocked)
        let p1 = c.projectedContract(throughMilestone: 1)
        #expect(p1.criteria.map(\.text) == ["build green", "tests pass", "docs updated"])
    }

    @Test("ladderIsValidPartition accepts a disjoint cover and rejects a gap")
    func partition() {
        #expect(laddered().ladderIsValidPartition())
        var gap = laddered()
        gap.milestones = [gap.milestones[0]]     // drops criteria b and c
        #expect(!gap.ladderIsValidPartition())
        #expect(GoalContract(objective: "x", criteria: []).ladderIsValidPartition())  // no ladder is valid
    }

    @Test("normalizedLadder folds unassigned criteria into a final milestone and clamps index")
    func normalize() {
        var gap = laddered()
        gap.milestones = [gap.milestones[0]]     // b and c now unassigned
        gap.currentMilestone = 9
        let n = gap.normalizedLadder()
        #expect(n.milestones.count == 2)
        #expect(n.milestones.last?.criterionIds.count == 2)   // b and c folded in
        #expect(n.currentMilestone == 1)                       // clamped to last index
    }

    @Test("ladder round-trips through Codable and legacy contracts decode to no ladder")
    func codable() throws {
        var c = laddered(); c.lock()
        let back = try JSONDecoder().decode(GoalContract.self, from: JSONEncoder().encode(c))
        #expect(back == c)
        // A contract encoded without ladder fields (simulated by a plain contract) has an empty ladder.
        let legacy = GoalContract(objective: "old", criteria: [Criterion(text: "y", kind: .qualitative, check: nil)])
        let legacyBack = try JSONDecoder().decode(GoalContract.self, from: JSONEncoder().encode(legacy))
        #expect(!legacyBack.hasLadder)
        #expect(legacyBack.checkpointStatus == .running)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter GoalContractLadderTests`
Expected: FAIL — `Milestone`, `CheckpointStatus`, and the new members don't exist yet (compile error).

- [ ] **Step 3: Implement the types, fields, and helpers**

In `Sources/iris/GoalContract.swift`, after the `Criterion` struct add:

```swift
struct Milestone: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var title: String
    var criterionIds: [UUID]
}

enum CheckpointStatus: String, Codable, Sendable, Equatable {
    case running          // loop active (or no ladder)
    case pausedForReview  // reached a checkpoint; auto-reprompt suppressed, awaiting the human
}
```

In `struct GoalContract`, add the fields **before** `var state: ContractState = .draft` (declaration order matters: Task 3's parsing calls the synthesized memberwise init with `milestones:` before `state:`, so `state` must remain the last stored property). Change the `changeLog`/`state` region to:

```swift
    var changeLog: [ContractChange] = []
    var milestones: [Milestone] = []          // empty ⇒ no ladder ⇒ today's single-terminal behavior
    var currentMilestone: Int = 0             // index of the milestone being worked
    var checkpointStatus: CheckpointStatus = .running
    var state: ContractState = .draft
```

Then add the helpers inside `GoalContract`:

```swift
    var hasLadder: Bool { !milestones.isEmpty }
    var isFinalMilestone: Bool { currentMilestone >= milestones.count - 1 }

    func currentMilestoneCriteria() -> [Criterion] {
        guard hasLadder, milestones.indices.contains(currentMilestone) else { return criteria }
        let ids = Set(milestones[currentMilestone].criterionIds)
        return criteria.filter { ids.contains($0.id) }
    }

    /// A locked copy whose criteria are the cumulative set across milestones 0...n, with the ladder
    /// stripped, ready to hand to GoalEvaluator.evaluate() unchanged (spec §6).
    func projectedContract(throughMilestone n: Int) -> GoalContract {
        let clamped = max(0, min(n, milestones.count - 1))
        let ids = Set(milestones.prefix(clamped + 1).flatMap { $0.criterionIds })
        var copy = self
        copy.criteria = criteria.filter { ids.contains($0.id) }
        copy.milestones = []
        copy.currentMilestone = 0
        copy.state = .locked
        return copy
    }

    /// True iff the ladder is a disjoint cover of `criteria`. An empty ladder is valid (no ladder).
    func ladderIsValidPartition() -> Bool {
        guard hasLadder else { return true }
        let assigned = milestones.flatMap { $0.criterionIds }
        let assignedSet = Set(assigned)
        if assigned.count != assignedSet.count { return false }   // a criterion in two milestones
        return assignedSet == Set(criteria.map { $0.id })          // covering, no stray ids
    }

    /// Repairs a hand-edited/legacy ladder: drops ids with no criterion, folds any unassigned
    /// criteria into an implicit final milestone, drops empty milestones, clamps currentMilestone.
    func normalizedLadder() -> GoalContract {
        var copy = self
        guard copy.hasLadder else { copy.currentMilestone = 0; return copy }
        let realIds = Set(copy.criteria.map { $0.id })
        for i in copy.milestones.indices {
            copy.milestones[i].criterionIds = copy.milestones[i].criterionIds.filter { realIds.contains($0) }
        }
        let assigned = Set(copy.milestones.flatMap { $0.criterionIds })
        let unassigned = copy.criteria.map { $0.id }.filter { !assigned.contains($0) }
        if !unassigned.isEmpty {
            copy.milestones.append(Milestone(title: "Remaining", criterionIds: unassigned))
        }
        copy.milestones.removeAll { $0.criterionIds.isEmpty }
        copy.currentMilestone = copy.milestones.isEmpty ? 0 : max(0, min(copy.currentMilestone, copy.milestones.count - 1))
        return copy
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter GoalContractLadderTests`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/iris/GoalContract.swift Tests/irisTests/GoalContractLadderTests.swift
git commit -m "feat(goal): milestone/ladder data model on GoalContract (slice B1, #13)"
```

---

### Task 2: Render the ladder in `oracleText()`

**Files:**
- Modify: `Sources/iris/GoalContract.swift` (the `oracleText()` method, ~L52-68)
- Test: `Tests/irisTests/GoalContractLadderTests.swift` (add to the existing suite)

**Interfaces:**
- Consumes: `hasLadder`, `currentMilestone`, `currentMilestoneCriteria()`, `milestones`, `isFinalMilestone` (Task 1).
- Produces: `oracleText()` gains a ladder block naming the current checkpoint and instructing the agent to call `reach_checkpoint` at non-final milestones and `goal_complete` only at the final one.

- [ ] **Step 1: Write the failing test**

Add to `GoalContractLadderTests`:

```swift
    @Test("oracleText names the current checkpoint and the reach_checkpoint instruction")
    func oracleLadder() {
        var c = laddered(); c.lock()
        let t = c.oracleText()
        #expect(t.contains("Current checkpoint"))
        #expect(t.contains("Compile"))                 // current milestone title
        #expect(t.contains("reach_checkpoint"))
        #expect(t.contains("goal_complete"))
        // A no-ladder contract keeps the plain oracle (no checkpoint language).
        let plain = GoalContract(objective: "x", criteria: [Criterion(text: "y", kind: .qualitative, check: nil)])
        #expect(!plain.oracleText().contains("Current checkpoint"))
    }
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter oracleLadder`
Expected: FAIL — no "Current checkpoint" substring.

- [ ] **Step 3: Extend `oracleText()`**

In `oracleText()`, before the final `return s`, insert:

```swift
        if hasLadder {
            let idx = min(max(currentMilestone, 0), milestones.count - 1)
            let m = milestones[idx]
            s += "\n## Checkpoint ladder (\(idx + 1) of \(milestones.count))\n"
            s += "Current checkpoint: \(m.title). Its definition of done is exactly these criteria:\n"
            for c in currentMilestoneCriteria() { s += "  - \(c.text)\n" }
            let upcoming = milestones.dropFirst(idx + 1)
            if !upcoming.isEmpty {
                s += "Upcoming checkpoints: " + upcoming.map { $0.title }.joined(separator: " → ") + "\n"
            }
            s += isFinalMilestone
                ? "This is the FINAL checkpoint — when its criteria hold, call `goal_complete`.\n"
                : "When THIS checkpoint's criteria hold, call `reach_checkpoint` (not `goal_complete`) — the run pauses for the user to review before the next checkpoint.\n"
        }
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --filter GoalContractLadderTests`
Expected: PASS (7 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/iris/GoalContract.swift Tests/irisTests/GoalContractLadderTests.swift
git commit -m "feat(goal): render checkpoint ladder in oracleText (slice B1, #13)"
```

---

### Task 3: Parse proposed milestones from `propose_goal_contract`

**Files:**
- Modify: `Sources/iris/GoalContractParsing.swift`
- Modify: `Sources/iris/iris.swift` (the `propose_goal_contract` tool schema, ~L401-419)
- Test: `Tests/irisTests/GoalContractParsingTests.swift` (add to the existing suite)

**Interfaces:**
- Consumes: `GoalContractParsing.contract(from:)`, `Milestone` (Task 1).
- Produces: `contract(from:)` reads an optional per-criterion `milestone` label, groups criteria by first-appearance label into ordered `Milestone`s, and returns a contract with `milestones` populated (empty when no criterion carries a label).

Rationale: a per-criterion label avoids fragile index/text cross-references — each `Criterion` already has a fresh `UUID` at parse time, so grouping by label maps directly to ids.

- [ ] **Step 1: Write the failing test**

Add to `GoalContractParsingTests` (mirror the existing style — build `[String: JSONValue]` args):

```swift
    @Test("per-criterion milestone labels group into an ordered ladder")
    func parsesMilestones() {
        let args: [String: JSONValue] = [
            "objective": .string("Ship it"),
            "criteria": .array([
                .object(["text": .string("build green"), "kind": .string("executable"),
                         "check": .string("swift build"), "milestone": .string("Compile")]),
                .object(["text": .string("docs updated"), "kind": .string("qualitative"),
                         "milestone": .string("Verify")]),
                .object(["text": .string("tests pass"), "kind": .string("executable"),
                         "check": .string("swift test"), "milestone": .string("Compile")]),
            ])
        ]
        let contract = GoalContractParsing.contract(from: args)
        #expect(contract?.milestones.map(\.title) == ["Compile", "Verify"])       // first-appearance order
        #expect(contract?.milestones.first?.criterionIds.count == 2)              // build + tests
        #expect(contract?.ladderIsValidPartition() == true)
    }

    @Test("no milestone labels yields no ladder")
    func parsesNoMilestones() {
        let args: [String: JSONValue] = [
            "objective": .string("Ship it"),
            "criteria": .array([.object(["text": .string("x"), "kind": .string("qualitative")])])
        ]
        #expect(GoalContractParsing.contract(from: args)?.hasLadder == false)
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter GoalContractParsingTests`
Expected: FAIL — `milestones` is empty (parsing ignores the label).

- [ ] **Step 3: Implement parsing**

In `GoalContractParsing.swift`, replace the criteria-building loop and the `return` so labels are captured in order. Full updated body of `contract(from:)` after the `strings` helper:

```swift
        var criteria: [Criterion] = []
        var order: [String] = []                 // milestone titles in first-appearance order
        var groups: [String: [UUID]] = [:]
        if case .array(let arr)? = args["criteria"] {
            for item in arr {
                guard case .object(let obj) = item, let text = obj["text"]?.stringValue else { continue }
                let kind = CriterionKind(rawValue: obj["kind"]?.stringValue ?? "") ?? .qualitative
                let check = kind == .executable ? obj["check"]?.stringValue : nil
                let criterion = Criterion(text: text, kind: kind, check: check)
                criteria.append(criterion)
                if let label = obj["milestone"]?.stringValue,
                   !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    if groups[label] == nil { order.append(label) }
                    groups[label, default: []].append(criterion.id)
                }
            }
        }
        let milestones = order.map { Milestone(title: $0, criterionIds: groups[$0] ?? []) }

        return GoalContract(objective: objective,
                            criteria: criteria,
                            outOfScope: strings("out_of_scope"),
                            stopBefore: strings("stop_before"),
                            assumptions: strings("assumptions"),
                            milestones: milestones,
                            state: .draft)
```

> Note: `GoalContract`'s memberwise initializer already accepts `milestones:` (it's a stored property with a default). `currentMilestone`/`checkpointStatus` keep their defaults.

In `iris.swift`, extend the `propose_goal_contract` criteria item schema (~L408-412) to advertise the label — add one property to the item `Schema`:

```swift
                        "milestone": Schema(type: "STRING", description: "Optional. A short checkpoint name; criteria sharing a name form one ordered checkpoint. Omit for a goal with no checkpoints.")
```

Also append one sentence to the tool `description` (~L403): `" Optionally group criteria into ordered checkpoints via a per-criterion 'milestone' label; the run pauses at each checkpoint for the user."`

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter GoalContractParsingTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/iris/GoalContractParsing.swift Sources/iris/iris.swift Tests/irisTests/GoalContractParsingTests.swift
git commit -m "feat(goal): parse per-criterion milestone labels into a ladder (slice B1, #13)"
```

---

### Task 4: AppState pause / advance / hold + normalize-on-lock

**Files:**
- Modify: `Sources/iris/AppState.swift` (near the goal helpers, ~L619-743; the `Conversation` decoder, ~L84-97)
- Test: `Tests/irisTests/GoalCheckpointStateTests.swift` (create)

**Interfaces:**
- Consumes: `GoalContract` ladder helpers (Task 1), existing `setGoalContract`, `saveConversations`, `runThinkingTask`, `engine.processInput`.
- Produces (all `@MainActor` on `AppState`):
  - `func setCheckpointPaused(for conversationId: UUID)` — sets `checkpointStatus = .pausedForReview`; leaves `activeGoal` set.
  - `func advanceCheckpoint(for conversationId: UUID)` — `currentMilestone += 1` (clamped), `checkpointStatus = .running`, then resumes the loop toward the next milestone.
  - `func holdCheckpoint(for conversationId: UUID, feedback: String?)` — `checkpointStatus = .running`, `currentMilestone` unchanged, resumes with steering + `not_met` context.
  - `setGoalContract` normalizes the ladder on lock.
  - `Conversation`'s decoder normalizes the ladder on load.

- [ ] **Step 1: Write the failing tests**

Create `Tests/irisTests/GoalCheckpointStateTests.swift`:

```swift
import Testing
import Foundation
@testable import iris

@MainActor
@Suite("Goal checkpoint state")
struct GoalCheckpointStateTests {
    private func lockedLadder(on app: AppState, _ id: UUID) {
        app.createNewConversation(id: id)
        let a = Criterion(text: "build", kind: .executable, check: "swift build")
        let b = Criterion(text: "docs", kind: .qualitative, check: nil)
        var c = GoalContract(objective: "Ship", criteria: [a, b])
        c.milestones = [Milestone(title: "Compile", criterionIds: [a.id]),
                        Milestone(title: "Verify", criterionIds: [b.id])]
        app.setGoalContract(for: id, c)   // locks + normalizes
    }

    @Test("setCheckpointPaused pauses without clearing the goal")
    func pauses() {
        let app = AppState(); let id = UUID(); lockedLadder(on: app, id)
        app.setCheckpointPaused(for: id)
        let conv = app.conversations.first { $0.id == id }
        #expect(conv?.goalContract?.checkpointStatus == .pausedForReview)
        #expect(conv?.activeGoal != nil)                 // loop gate intact
        #expect(conv?.goalContract?.currentMilestone == 0)
    }

    @Test("advanceCheckpoint moves to the next milestone and resumes")
    func advances() {
        let app = AppState(); let id = UUID(); lockedLadder(on: app, id)
        app.setCheckpointPaused(for: id)
        app.advanceCheckpoint(for: id)
        let conv = app.conversations.first { $0.id == id }
        #expect(conv?.goalContract?.currentMilestone == 1)
        #expect(conv?.goalContract?.checkpointStatus == .running)
    }

    @Test("advanceCheckpoint clamps at the final milestone")
    func advanceClamps() {
        let app = AppState(); let id = UUID(); lockedLadder(on: app, id)
        app.advanceCheckpoint(for: id)   // -> 1 (final)
        app.advanceCheckpoint(for: id)   // stays 1
        #expect(app.conversations.first { $0.id == id }?.goalContract?.currentMilestone == 1)
    }

    @Test("holdCheckpoint keeps the milestone and resumes")
    func holds() {
        let app = AppState(); let id = UUID(); lockedLadder(on: app, id)
        app.setCheckpointPaused(for: id)
        app.holdCheckpoint(for: id, feedback: "not done")
        let conv = app.conversations.first { $0.id == id }
        #expect(conv?.goalContract?.currentMilestone == 0)     // unchanged
        #expect(conv?.goalContract?.checkpointStatus == .running)
    }

    @Test("setGoalContract normalizes an incomplete ladder on lock")
    func normalizesOnLock() {
        let app = AppState(); let id = UUID()
        app.createNewConversation(id: id)
        let a = Criterion(text: "a", kind: .qualitative, check: nil)
        let b = Criterion(text: "b", kind: .qualitative, check: nil)
        var c = GoalContract(objective: "x", criteria: [a, b])
        c.milestones = [Milestone(title: "Only", criterionIds: [a.id])]   // b unassigned
        app.setGoalContract(for: id, c)
        let stored = app.conversations.first { $0.id == id }?.goalContract
        #expect(stored?.ladderIsValidPartition() == true)                  // b folded into a final milestone
        #expect(stored?.milestones.count == 2)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter GoalCheckpointStateTests`
Expected: FAIL — `setCheckpointPaused`/`advanceCheckpoint`/`holdCheckpoint` don't exist; lock doesn't normalize.

- [ ] **Step 3: Implement the AppState methods and normalization**

In `AppState.swift`, in `setGoalContract` (~L689), normalize before locking. Change:

```swift
        var locked = contract
        locked.lock()
```
to:
```swift
        var locked = contract.normalizedLadder()
        locked.lock()
```

Add these methods near the other goal helpers (after `amendGoalContract`, ~L723):

```swift
    /// Marks the goal as paused at a checkpoint. Leaves `activeGoal` set so the loop gate is intact;
    /// the engine's auto-reprompt reads `checkpointStatus` and stays quiet (spec §6, §10).
    func setCheckpointPaused(for conversationId: UUID) {
        guard let idx = conversations.firstIndex(where: { $0.id == conversationId }),
              var c = conversations[idx].goalContract else { return }
        c.checkpointStatus = .pausedForReview
        conversations[idx].goalContract = c
        saveConversations()
    }

    /// Human approved the checkpoint: advance to the next milestone and resume the loop.
    func advanceCheckpoint(for conversationId: UUID) {
        guard let idx = conversations.firstIndex(where: { $0.id == conversationId }),
              var c = conversations[idx].goalContract, c.hasLadder else { return }
        c.currentMilestone = min(c.currentMilestone + 1, c.milestones.count - 1)
        c.checkpointStatus = .running
        conversations[idx].goalContract = c
        saveConversations()
        resumeGoalLoop(for: conversationId, steer: nil)
    }

    /// Human sent the agent back to keep working the current milestone (no advance).
    func holdCheckpoint(for conversationId: UUID, feedback: String?) {
        guard let idx = conversations.firstIndex(where: { $0.id == conversationId }),
              var c = conversations[idx].goalContract else { return }
        c.checkpointStatus = .running
        conversations[idx].goalContract = c
        saveConversations()
        resumeGoalLoop(for: conversationId, steer: feedback)
    }

    /// Re-arms the goal loop after a checkpoint resume by sending a fresh oracle reprompt.
    private func resumeGoalLoop(for conversationId: UUID, steer: String?) {
        guard let conv = conversations.first(where: { $0.id == conversationId }),
              let contract = conv.goalContract else { return }
        let steerLine = (steer?.isEmpty == false) ? "\n\nHuman feedback at this checkpoint: \(steer!)" : ""
        let reprompt = "\(contract.oracleText())\(steerLine)\n\nContinue toward the current checkpoint. What is your next step?"
        runThinkingTask(conversationId: conversationId) { [self] in
            await engine.processInput(reprompt, source: "System", conversationId: conversationId)
        }
    }
```

In the `Conversation` decoder (~L88, right after `goalContract = try container.decodeIfPresent(...)` and before/after the legacy migration block ~L93-97), normalize any decoded ladder:

```swift
        if let gc = goalContract { goalContract = gc.normalizedLadder() }
```
Place this AFTER the legacy `activeGoal`→contract migration so a migrated single-criterion contract (no ladder) passes through unchanged.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter GoalCheckpointStateTests`
Expected: PASS (6 tests).

> Note: `resumeGoalLoop` calls `engine.processInput`; in these unit tests the resume methods still mutate and persist state synchronously before the async reprompt task runs, so the assertions (which read state immediately) hold. The reprompt behavior itself is covered in Task 6.

- [ ] **Step 5: Commit**

```bash
git add Sources/iris/AppState.swift Tests/irisTests/GoalCheckpointStateTests.swift
git commit -m "feat(goal): checkpoint pause/advance/hold state + normalize-on-load (slice B1, #13)"
```

---

### Task 5: `reach_checkpoint` tool + handler

**Files:**
- Modify: `Sources/iris/iris.swift` (tool definition near `goal_complete` ~L341-356; conditional offering; handler near the `goal_complete` handler ~L790-824)
- Test: `Tests/irisTests/ReachCheckpointHandlerTests.swift` (create)

**Interfaces:**
- Consumes: `GoalContract` ladder helpers + `projectedContract` (Task 1), `AppState.setCheckpointPaused` + `beginGoalEvaluation` (Task 4 / existing), `GoalEvaluator.shared.evaluate(...)` (existing, unmodified), `ScriptedLLMClient`.
- Produces: a `reach_checkpoint` tool offered only when `hasLadder && !isFinalMilestone`; a handler that (final-milestone) routes to `goal_complete` guidance, else records the self-report, awaits a cumulative grade, and sets `pausedForReview` without clearing `activeGoal`.

- [ ] **Step 1: Write the failing test**

Create `Tests/irisTests/ReachCheckpointHandlerTests.swift`. Model the response builder on `GoalCompleteStatusTests`:

```swift
import Testing
import Foundation
@testable import iris

private func reachCheckpointResponse(summary: String) -> GeminiResponse {
    let call = FunctionCall(name: "reach_checkpoint",
                            args: ["milestone_summary": .string(summary)],
                            id: nil, thought_signature: nil, thoughtSignature: nil)
    let part = Part(text: nil, functionCall: call, functionResponse: nil,
                    thought_signature: nil, thoughtSignature: nil)
    return GeminiResponse(candidates: [Candidate(content: Content(role: "model", parts: [part]))],
                          usageMetadata: nil)
}

// A grader response that submits an empty evaluation, so GoalEvaluator resolves quickly.
private func submitEvaluationResponse() -> GeminiResponse {
    let call = FunctionCall(name: "submit_evaluation",
                            args: ["evaluations": .array([])],
                            id: nil, thought_signature: nil, thoughtSignature: nil)
    let part = Part(text: nil, functionCall: call, functionResponse: nil,
                    thought_signature: nil, thoughtSignature: nil)
    return GeminiResponse(candidates: [Candidate(content: Content(role: "model", parts: [part]))],
                          usageMetadata: nil)
}

@MainActor
@Suite("reach_checkpoint handler")
struct ReachCheckpointHandlerTests {
    private func lockLadder(on app: AppState, _ id: UUID) {
        app.createNewConversation(id: id)
        let a = Criterion(text: "build", kind: .qualitative, check: nil)
        let b = Criterion(text: "docs", kind: .qualitative, check: nil)
        var c = GoalContract(objective: "Ship", criteria: [a, b])
        c.milestones = [Milestone(title: "One", criterionIds: [a.id]),
                        Milestone(title: "Two", criterionIds: [b.id])]
        app.setGoalContract(for: id, c)
    }

    @Test("reach_checkpoint pauses without clearing the goal and records an evaluation")
    func pausesAndGrades() async {
        let app = AppState(); let id = UUID(); lockLadder(on: app, id)
        // First the working agent calls reach_checkpoint; then the grader (fresh convo) submits.
        let mock = ScriptedLLMClient(responses: [
            reachCheckpointResponse(summary: "milestone one done"),
            submitEvaluationResponse(),
        ])
        let engine = IrisEngine(state: app, tier: .medium, principal: .main, client: mock)
        await engine.processInput("work", source: "User", conversationId: id)

        let conv = app.conversations.first { $0.id == id }
        #expect(conv?.goalContract?.checkpointStatus == .pausedForReview)
        #expect(conv?.activeGoal != nil)                      // NOT cleared (contrast goal_complete)
        #expect(conv?.goalContract?.currentMilestone == 0)    // not advanced by the handler
        #expect(conv?.lastGoalEvaluation != nil)              // a grade landed
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter ReachCheckpointHandlerTests`
Expected: FAIL — `reach_checkpoint` is an unknown tool; the handler falls through and never pauses.

- [ ] **Step 3: Define the tool (conditionally offered)**

In `iris.swift`, after the `goal_complete` `toolsList.append(...)` block (~L356), add the conditional offer. First resolve ladder state once (place near the other MainActor reads in `processInputBody`, before the tool list is finalized ~L440):

```swift
        let ladderContract = await MainActor.run {
            localState?.conversations.first(where: { $0.id == conversationId })?.goalContract
        }
        if principal == .main, let gc = ladderContract, gc.hasLadder, !gc.isFinalMilestone {
            toolsList.append(FunctionDeclaration(
                name: "reach_checkpoint",
                description: "Signal that the CURRENT checkpoint's criteria are satisfied. The run pauses and an independent evaluator grades the work so far; the user then reviews before the next checkpoint. Use goal_complete only at the final checkpoint.",
                parameters: Schema(
                    type: "OBJECT",
                    properties: [
                        "milestone_summary": Schema(type: "STRING", description: "What you accomplished for this checkpoint."),
                        "criteria_status": Schema(type: "ARRAY", description: "Per-criterion self-report for this checkpoint. Shown to the user as UNVERIFIED.", items: Schema(type: "OBJECT", properties: [
                            "criterion": Schema(type: "STRING", description: "The criterion text."),
                            "status": Schema(type: "STRING", description: "met | not_met | cannot_verify"),
                            "evidence": Schema(type: "STRING", description: "Brief evidence.")
                        ], required: ["criterion", "status"]))
                    ],
                    required: ["milestone_summary"]
                )
            ))
        }
```

> Placement: this must run before `toolsList = ToolIntent.augment(toolsList)` (~L435) so `reach_checkpoint` gets the `intent` augmentation and passes the array-items assertion (~L445).

- [ ] **Step 4: Implement the handler**

In `executeFunctionCall`, add a branch before the final `else` (mirror the `goal_complete` branch at ~L790). Insert after the `goal_complete` block ends (~L824):

```swift
        } else if functionCall.name == "reach_checkpoint", principal == .main {
            let summary = functionCall.args["milestone_summary"]?.stringValue ?? ""
            let statusReport = functionCall.args["criteria_status"]
            let contract = await MainActor.run {
                localState?.conversations.first(where: { $0.id == conversationId })?.goalContract
            }
            guard let contract, contract.hasLadder else {
                result = "No checkpoint ladder is active. Call goal_complete when the goal is finished."
                return result
            }
            if contract.isFinalMilestone {
                result = "This is the final checkpoint — call `goal_complete` to finish, not `reach_checkpoint`."
                return result
            }
            let projected = contract.projectedContract(throughMilestone: contract.currentMilestone)
            let gradeWorkspace = workspacePath ?? FileManager.default.currentDirectoryPath
            await MainActor.run {
                localState?.recordCompletionSelfReport(for: conversationId, statusJSON: statusReport)
                localState?.beginGoalEvaluation(for: conversationId, contract: projected)
                localState?.setCheckpointPaused(for: conversationId)   // leaves activeGoal set
            }
            // Await the grade (unlike goal_complete's detached grade) — the human should see the
            // verdict before re-engaging. The reprompt guard (Task 6) keeps the loop quiet meanwhile.
            let graderClient = self.client
            if let graderApp = localState {
                await GoalEvaluator.shared.evaluate(contract: projected, workspace: gradeWorkspace,
                                                    originatingConversationId: conversationId,
                                                    app: graderApp, client: graderClient)
            }
            let ladderPos = "\(contract.currentMilestone + 1) of \(contract.milestones.count)"
            await pushToUI(role: .agent, text: "Reached checkpoint \(ladderPos): \(summary)\nPaused for your review — approve to continue or send me back.", conversationId: conversationId)
            result = "Checkpoint \(ladderPos) reached and graded. Paused for user review."
```

> `return result` early-exits use the same pattern as the surrounding handler? Confirm the enclosing function returns `String`; if it uses fallthrough rather than early return, replace `return result` with setting `result` and guarding the rest with `else`. (The function is `executeFunctionCall(...) -> String`; early `return result` is valid.)

- [ ] **Step 5: Run the test to verify it passes**

Run: `swift test --filter ReachCheckpointHandlerTests`
Expected: PASS.

- [ ] **Step 6: Run the full goal suite to confirm no `goal_complete` regression**

Run: `swift test --filter Goal`
Expected: PASS (existing GoalComplete*/GoalContract*/GoalEvaluator* suites still green).

- [ ] **Step 7: Commit**

```bash
git add Sources/iris/iris.swift Tests/irisTests/ReachCheckpointHandlerTests.swift
git commit -m "feat(goal): reach_checkpoint tool + pausing handler (slice B1, #13)"
```

---

### Task 6: Suppress the auto-reprompt while paused

**Files:**
- Modify: `Sources/iris/iris.swift` (the auto-reprompt block, ~L661-696)
- Test: `Tests/irisTests/CheckpointRepromptTests.swift` (create)

**Interfaces:**
- Consumes: `checkpointStatus` on the persisted contract (Task 1), the existing auto-reprompt block.
- Produces: while `checkpointStatus == .pausedForReview`, the loop ends the turn — no auto-reprompt, no soft-stop.

- [ ] **Step 1: Write the failing test**

Create `Tests/irisTests/CheckpointRepromptTests.swift`. Assert that after a `reach_checkpoint` turn, the paused conversation does NOT emit the "Auto-continuing goal loop" system message:

```swift
import Testing
import Foundation
@testable import iris

@MainActor
@Suite("Checkpoint reprompt suppression")
struct CheckpointRepromptTests {
    @Test("a paused checkpoint does not auto-reprompt")
    func pausedDoesNotReprompt() async {
        let app = AppState(); let id = UUID()
        app.createNewConversation(id: id)
        let a = Criterion(text: "build", kind: .qualitative, check: nil)
        let b = Criterion(text: "docs", kind: .qualitative, check: nil)
        var c = GoalContract(objective: "Ship", criteria: [a, b])
        c.milestones = [Milestone(title: "One", criterionIds: [a.id]),
                        Milestone(title: "Two", criterionIds: [b.id])]
        app.setGoalContract(for: id, c)

        // reach_checkpoint, then a grader submit. If the loop wrongly reprompted, the scripted
        // client would run dry and the test would surface extra turns.
        let reach = FunctionCall(name: "reach_checkpoint", args: ["milestone_summary": .string("done")],
                                 id: nil, thought_signature: nil, thoughtSignature: nil)
        let reachResp = GeminiResponse(candidates: [Candidate(content: Content(role: "model",
                          parts: [Part(text: nil, functionCall: reach, functionResponse: nil,
                                       thought_signature: nil, thoughtSignature: nil)]))], usageMetadata: nil)
        let submit = FunctionCall(name: "submit_evaluation", args: ["evaluations": .array([])],
                                  id: nil, thought_signature: nil, thoughtSignature: nil)
        let submitResp = GeminiResponse(candidates: [Candidate(content: Content(role: "model",
                          parts: [Part(text: nil, functionCall: submit, functionResponse: nil,
                                       thought_signature: nil, thoughtSignature: nil)]))], usageMetadata: nil)
        let mock = ScriptedLLMClient(responses: [reachResp, submitResp])
        let engine = IrisEngine(state: app, tier: .medium, principal: .main, client: mock)
        await engine.processInput("work", source: "User", conversationId: id)

        let conv = app.conversations.first { $0.id == id }
        #expect(conv?.goalContract?.checkpointStatus == .pausedForReview)
        // No "Auto-continuing goal loop" system message was pushed for this conversation.
        let autoContinue = conv?.messages.contains { $0.content.contains("Auto-continuing goal loop") } ?? false
        #expect(!autoContinue)
    }
}
```

> If `ChatMessage`'s text property isn't `content`, adjust to the actual accessor used elsewhere in the tests (grep `GoalCompleteTests` for how it reads pushed messages).

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter CheckpointRepromptTests`
Expected: FAIL — without the guard, the paused goal auto-reprompts and pushes "Auto-continuing goal loop".

- [ ] **Step 3: Add the suppression guard**

In `iris.swift`, in the auto-reprompt block (~L670), gate on the paused status. Change:

```swift
        if let _ = activeGoalResult.0 {
            if activeGoalResult.1 >= ConfigManager.shared.maxGoalIterations {
```
to:
```swift
        let pausedForReview = await MainActor.run {
            localState?.conversations.first(where: { $0.id == conversationId })?.goalContract?.checkpointStatus == .pausedForReview
        }
        if let _ = activeGoalResult.0, !pausedForReview {
            if activeGoalResult.1 >= ConfigManager.shared.maxGoalIterations {
```

This leaves the existing `else`/reprompt body unchanged; a paused goal simply ends the turn (both the soft-stop branch and the reprompt branch are skipped — spec §6 step 5 / §10).

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --filter CheckpointRepromptTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/iris/iris.swift Tests/irisTests/CheckpointRepromptTests.swift
git commit -m "feat(goal): suppress auto-reprompt while paused at a checkpoint (slice B1, #13)"
```

---

### Task 7: Ladder authoring + pause UI in `GoalContractPanel`

**Files:**
- Modify: `Sources/iris/GoalContractPanel.swift`
- Test: build + manual verification (SwiftUI view; no unit test harness in this repo for views)

**Interfaces:**
- Consumes: the panel's existing local editable contract copy, `approveAndLock()` (~L167), `state.setGoalContract` / `state.sendGoalKickoff` (~L187-188), `state.advanceCheckpoint` / `state.holdCheckpoint` (Task 4), `GoalContract.checkpointStatus` / `milestones` / `currentMilestone` / `lastGoalEvaluation`.
- Produces: draft milestone assignment UI, a locked-run ladder view, and pause affordances (Approve & continue / Send back).

- [ ] **Step 1: Draft editing — assign criteria to milestones**

In the draft section of the panel, render criteria grouped by milestone. For each criterion, add a control to set its milestone title (a `TextField` or `Menu` of existing milestone titles + "New…"). Maintain the edited `milestones` array on the local copy so labels group into `Milestone`s the same way parsing does. Show an inline warning when `!edited.ladderIsValidPartition()` (unassigned criteria) and disable "Approve & Lock" until valid OR the user clears all milestones (choosing "no checkpoints"). Because `setGoalContract` calls `normalizedLadder()`, a minor gap is still repaired on lock, but the warning keeps authoring honest.

Guidance for the grouping control (adapt to the panel's existing row layout):

```swift
// Per-criterion milestone assignment (draft only).
Picker("Checkpoint", selection: milestoneBinding(for: criterion)) {
    Text("— none —").tag(String?.none)
    ForEach(edited.milestones.map(\.title), id: \.self) { Text($0).tag(String?.some($0)) }
}
```
`milestoneBinding(for:)` reads/writes which milestone a criterion id belongs to, rebuilding `edited.milestones` (preserving first-appearance order) on change.

- [ ] **Step 2: Locked-run ladder view**

When `contract.isLocked && contract.hasLadder`, render a compact vertical ladder: each milestone titled, marked **done** (`index < currentMilestone`), **current** (`== currentMilestone`), or **upcoming** (`> currentMilestone`). Keep it visually subordinate to the existing criteria list.

- [ ] **Step 3: Pause affordances**

When `contract.checkpointStatus == .pausedForReview`, highlight the current rung and show:
- The milestone self-report (from `lastGoalCompletionReport`) marked **UNVERIFIED** (reuse the existing self-report rendering).
- The trusted verdict from `lastGoalEvaluation` (reuse the existing `CriterionVerdict` rendering at ~L516).
- Two buttons:

```swift
Button("Approve & continue") { state.advanceCheckpoint(for: conversation.id) }
Button("Send back") { state.holdCheckpoint(for: conversation.id, feedback: sendBackNote) }
```
`sendBackNote` is an optional `TextField` for steering (may be empty). Never render a milestone self-report as a passed gate (spec §8).

- [ ] **Step 4: Build and manually verify**

Run: `swift build`
Expected: builds clean.

Manual checklist (run the app, start a `/goal` that proposes ≥2 milestones):
- Draft panel groups criteria under milestone headers; unassigned-criteria warning appears and blocks lock until resolved.
- After lock, the ladder shows milestone 1 as current.
- When the agent calls `reach_checkpoint`, the run pauses, the ladder highlights the current rung, and the self-report (UNVERIFIED) + trusted verdict both render.
- "Approve & continue" advances to milestone 2 and the loop resumes; "Send back" keeps milestone 1 and resumes with the note.
- Quit and relaunch while paused: the paused chip reloads and the loop stays quiet until resumed (spec §7 restart behavior).

- [ ] **Step 5: Commit**

```bash
git add Sources/iris/GoalContractPanel.swift
git commit -m "feat(goal): ladder authoring + checkpoint pause UI in GoalContractPanel (slice B1, #13)"
```

---

### Task 8: Docs — record the shipped feature

**Files:**
- Modify: whichever doc enumerates goal/loop features (check `docs/` and `CLAUDE.md` for a goal-contract feature list; e.g. the slice-A/C specs' "larger arc" sections or a user-facing commands doc).

**Interfaces:** none (documentation).

- [ ] **Step 1: Update the arc status**

In `docs/specs/2026-08-01-goal-checkpoint-ladder.md`, change `Status` from `Approved (design)` to `Implemented`. If a top-level roadmap or `/goal` command doc lists slices, mark B1 (checkpoint ladder) done and note B2 (inner/outer loop) still pending. Per the repo's atomic Definition-of-Done rule (commit 7424cd4), docs update in the same change set as the feature — so this task ships with the branch, not after.

- [ ] **Step 2: Commit**

```bash
git add docs/
git commit -m "docs(goal): mark checkpoint ladder (slice B1) implemented (#13)"
```

---

## Self-Review

**Spec coverage:**
- §3 ladder / partition → Task 1 (`ladderIsValidPartition`, `normalizedLadder`).
- §4 data model (types, fields, helpers, invariants) → Task 1; normalize-on-load → Task 4; normalize-on-lock → Task 4.
- §5 `reach_checkpoint` tool + oracle instruction → Task 5 (tool, conditional offer) + Task 2 (oracle).
- §6 handler flow (final guard, self-report, cumulative await grade, pause, suppress, surface) → Task 5 (steps 1-4, 6) + Task 6 (step 5 suppression).
- §7 human-driven resume (advance / hold, restart persistence) → Task 4 + Task 7 step 3.
- §8 authoring + locked ladder + pause UI + unverified marking → Task 3 (parse) + Task 7.
- §9 edge cases: no-ladder tool not offered (Task 5 conditional), final-milestone route (Task 5 handler), evaluator-fail safety net (reused unmodified from C), hand-edited/legacy normalize (Task 1/4), subagent no-ladder (Task 5 `principal == .main` gate) → covered.
- §10 fixed constraints (#16, goal_complete, evaluator, SubagentManager untouched) → enforced by construction; Task 5 step 6 regression run guards it.
- §11 testing → Tasks 1-6 carry the listed unit/handler/loop tests; §11 restart test → Task 7 manual checklist (persistence is exercised by the Codable round-trip in Task 1 + normalize-on-load in Task 4).

**Placeholder scan:** no TBD/TODO; every code step carries real code. Task 7 (SwiftUI) is intentionally build+manual — this repo has no view-test harness — but each sub-step names concrete bindings, methods, and a verification checklist.

**Type consistency:** `Milestone`, `CheckpointStatus`, `hasLadder`, `isFinalMilestone`, `currentMilestoneCriteria()`, `projectedContract(throughMilestone:)`, `ladderIsValidPartition()`, `normalizedLadder()`, `setCheckpointPaused`, `advanceCheckpoint`, `holdCheckpoint(feedback:)`, `resumeGoalLoop(steer:)` — names used identically across Tasks 1, 2, 4, 5, 6, 7. The `reach_checkpoint` args (`milestone_summary`, `criteria_status`) match between the tool schema (Task 5 step 3) and the handler (Task 5 step 4) and tests (Task 5/6).
