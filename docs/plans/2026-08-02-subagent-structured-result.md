# Structured Inner-Loop Result (slice B2) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the subagent's opaque `String` return with a structured, versioned `SubagentResult` (terminal status + `goal_complete` flag + `write_file` ledger + an unverified summary), render it as prose for the parent, and persist the struct on the subagent conversation.

**Architecture:** A new `SubagentResult` value type carries hard facts and an unverified self-report. The four subagent termination sites hand a small `SubagentTermination` signal through `onSubagentComplete`; `SubagentManager` (the single assembly point) combines it with role, timing, and a drained per-conversation write-ledger into the final `SubagentResult`, persists it on the `Conversation`, and returns `renderedForParent()` prose. `goal_complete`, the B1 ladder, and the C evaluator are untouched.

**Tech Stack:** Swift 5.9+. Pure-type tests use Swift Testing (`import Testing`, `@Suite`/`@Test`/`#expect`). Subagent integration tests use XCTest + `MockURLProtocol` (mocks the LLM at the HTTP layer, mirroring the existing `SubagentManagerTests`).

## Global Constraints

- Spec: `docs/specs/2026-08-02-subagent-structured-result.md`. Every task traces to a section there.
- **`goal_complete` semantics must not change** — it stays the sole terminal path (clears the goal, self-reports, fires the main-agent background C grade + skill-check reflection). B2 only restructures what a *subagent's* completion delivers to its parent.
- **B1's checkpoint ladder is untouched** — `reach_checkpoint`, the pause, and `oracleText()` are not modified.
- **No inner-loop grading** — the C evaluator (`GoalEvaluator`) is NOT invoked for a subagent in B2. There is no unit contract to grade (that is B3).
- **Backwards compatibility:** the new `Conversation.subagentResult` field decodes with `decodeIfPresent` → `nil`. `Conversation` has a custom `init(from:)`; a field decoded without `decodeIfPresent` throws on a missing key and wipes every persisted conversation on load. This must not happen.
- New types are `Codable, Sendable, Equatable` to match the surrounding value types.
- The write-ledger records `write_file` successes only, and only for `isSubagent` conversations. `run_command` side effects are out of scope by construction.

---

### Task 1: `SubagentResult` types, prose rendering, and the persisted `Conversation` field

**Files:**
- Create: `Sources/iris/SubagentResult.swift`
- Modify: `Sources/iris/AppState.swift` (the `Conversation` struct: `CodingKeys` ~L73, `init(from:)` ~L76-90, add a stored field)
- Test: `Tests/irisTests/SubagentResultTests.swift` (create)

**Interfaces:**
- Consumes: nothing new.
- Produces:
  - `enum SubagentTerminalStatus: String, Codable, Sendable, Equatable { case completed, failed, timedOut, cancelled }`
  - `struct SubagentTermination: Sendable { var status; var summary; var calledGoalComplete }` (in-memory signal; not Codable)
  - `struct SubagentResult: Codable, Sendable, Equatable` with `schemaVersion, role, status, calledGoalComplete, summary, filesWritten, startedAt, endedAt`
  - `func renderedForParent() -> String` on `SubagentResult`
  - `Conversation.subagentResult: SubagentResult?`

- [ ] **Step 1: Write the failing tests**

Create `Tests/irisTests/SubagentResultTests.swift`:

```swift
import Testing
import Foundation
@testable import iris

@Suite("SubagentResult")
struct SubagentResultTests {
    private func sample(status: SubagentTerminalStatus = .completed,
                        calledGoalComplete: Bool = true,
                        files: [String] = ["Sources/A.swift", "Sources/B.swift"]) -> SubagentResult {
        SubagentResult(role: "engineer", status: status, calledGoalComplete: calledGoalComplete,
                       summary: "did the thing", filesWritten: files,
                       startedAt: Date(timeIntervalSince1970: 0), endedAt: Date(timeIntervalSince1970: 5))
    }

    @Test("SubagentResult round-trips through Codable")
    func codableRoundTrip() throws {
        let r = sample()
        let back = try JSONDecoder().decode(SubagentResult.self, from: JSONEncoder().encode(r))
        #expect(back == r)
        #expect(back.schemaVersion == 1)
    }

    @Test("a completed result renders status, goal_complete note, summary, and files")
    func renderCompleted() {
        let s = sample().renderedForParent()
        #expect(s.contains("status: completed"))
        #expect(s.contains("goal_complete called"))
        #expect(s.contains("did the thing"))
        #expect(s.contains("Files written (2)"))
        #expect(s.contains("Sources/A.swift"))
    }

    @Test("a failed result with no files renders 'failed' and omits the files line")
    func renderFailedNoFiles() {
        let s = sample(status: .failed, calledGoalComplete: false, files: []).renderedForParent()
        #expect(s.contains("status: failed"))
        #expect(s.contains("goal_complete not called"))
        #expect(!s.contains("Files written"))
    }

    @Test("timed-out and cancelled render human-readable status text")
    func renderOtherStatuses() {
        #expect(sample(status: .timedOut, calledGoalComplete: false, files: []).renderedForParent().contains("status: timed out"))
        #expect(sample(status: .cancelled, calledGoalComplete: false, files: []).renderedForParent().contains("status: cancelled"))
    }

    @Test("a Conversation with no subagentResult key decodes to nil (no wipe)")
    func legacyConversationDecodesToNil() throws {
        let conv = Conversation(title: "legacy")
        let back = try JSONDecoder().decode(Conversation.self, from: JSONEncoder().encode(conv))
        #expect(back.subagentResult == nil)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter SubagentResultTests`
Expected: FAIL — `SubagentResult`, `SubagentTerminalStatus`, `renderedForParent`, and `Conversation.subagentResult` don't exist (compile error).

- [ ] **Step 3: Create the types and rendering**

Create `Sources/iris/SubagentResult.swift`:

```swift
import Foundation

enum SubagentTerminalStatus: String, Codable, Sendable, Equatable {
    case completed   // goal_complete was called by the subagent
    case failed      // LLM/engine error ended the run
    case timedOut    // the poll cap in SubagentManager fired
    case cancelled   // stop/cancel path ended the run
}

/// In-memory termination signal handed from a termination site to SubagentManager.
/// Not Codable — SubagentManager immediately folds it into a SubagentResult.
struct SubagentTermination: Sendable {
    var status: SubagentTerminalStatus
    var summary: String
    var calledGoalComplete: Bool
}

struct SubagentResult: Codable, Sendable, Equatable {
    var schemaVersion = 1
    var role: String
    var status: SubagentTerminalStatus
    var calledGoalComplete: Bool
    var summary: String              // UNVERIFIED self-report — the subagent's own words
    var filesWritten: [String]       // deduped write_file paths
    var startedAt: Date
    var endedAt: Date

    func renderedForParent() -> String {
        let statusText: String
        switch status {
        case .completed: statusText = "completed"
        case .failed:    statusText = "failed"
        case .timedOut:  statusText = "timed out"
        case .cancelled: statusText = "cancelled"
        }
        let gc = calledGoalComplete ? "goal_complete called" : "goal_complete not called"
        var s = "Subagent '\(role)' finished — status: \(statusText) (\(gc)).\nSummary: \(summary)"
        if !filesWritten.isEmpty {
            s += "\nFiles written (\(filesWritten.count)): \(filesWritten.joined(separator: ", "))"
        }
        return s
    }
}
```

- [ ] **Step 4: Add the persisted field to `Conversation`**

In `Sources/iris/AppState.swift`, `struct Conversation`:

Add the stored property near `lastGoalEvaluation` (declaration order is free; it is set via a setter, not the memberwise init):
```swift
    var subagentResult: SubagentResult? = nil
```

Add `subagentResult` to the `CodingKeys` enum (~L73), appended after `lastGoalEvaluation`:
```swift
        case id, title, messages, workspacePath, history, tokenUsage, activeGoal, messageCountSinceReflection, mainAgentSandbox, isSubagent, goalContract, lastGoalCompletionReport, lastGoalEvaluation, subagentResult
```

In `init(from:)` (~L90, right after the `lastGoalEvaluation` decode), add:
```swift
        subagentResult = try container.decodeIfPresent(SubagentResult.self, forKey: .subagentResult)
```

> `Conversation` uses the compiler-synthesized `encode(to:)` (B1 added `lastGoalEvaluation` the same way — CodingKey + `decodeIfPresent`, no custom encoder). Adding the key is sufficient for encoding. If a hand-written `encode(to:)` is present, add `try container.encode(subagentResult, forKey: .subagentResult)` there too.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test --filter SubagentResultTests`
Expected: PASS (5 tests).

- [ ] **Step 6: Commit**

```bash
git add Sources/iris/SubagentResult.swift Sources/iris/AppState.swift Tests/irisTests/SubagentResultTests.swift
git commit -m "feat(subagent): SubagentResult type, prose rendering, persisted field (slice B2, #13)"
```

---

### Task 2: Files-written ledger on `AppState`

**Files:**
- Modify: `Sources/iris/AppState.swift` (add a ledger dict + methods near the subagent helpers ~L249-256; clear in `removeSubagent`)
- Test: `Tests/irisTests/SubagentWriteLedgerTests.swift` (create)

**Interfaces:**
- Consumes: existing `conversations`, `isSubagent`, `createNewConversation(id:isSubagent:)`, `removeSubagent(id:)`.
- Produces (all `@MainActor` on `AppState`):
  - `var subagentWriteLedger: [UUID: [String]]`
  - `func recordSubagentWrite(conversationId: UUID, path: String)` — only when the conversation `isSubagent`; deduped append.
  - `func drainSubagentWrites(for conversationId: UUID) -> [String]` — returns and clears the entry.
  - `removeSubagent` clears the ledger entry.

- [ ] **Step 1: Write the failing tests**

Create `Tests/irisTests/SubagentWriteLedgerTests.swift`:

```swift
import Testing
import Foundation
@testable import iris

@MainActor
@Suite("Subagent write ledger")
struct SubagentWriteLedgerTests {
    @Test("records deduped writes for a subagent conversation and drains once")
    func recordsAndDrains() {
        let app = AppState(); let id = UUID()
        app.createNewConversation(id: id, isSubagent: true)
        app.recordSubagentWrite(conversationId: id, path: "a.swift")
        app.recordSubagentWrite(conversationId: id, path: "a.swift")   // dup
        app.recordSubagentWrite(conversationId: id, path: "b.swift")
        #expect(app.drainSubagentWrites(for: id) == ["a.swift", "b.swift"])
        #expect(app.drainSubagentWrites(for: id) == [])                 // cleared
    }

    @Test("ignores writes for a non-subagent conversation")
    func ignoresMainAgent() {
        let app = AppState(); let id = UUID()
        app.createNewConversation(id: id)                               // isSubagent == false
        app.recordSubagentWrite(conversationId: id, path: "a.swift")
        #expect(app.drainSubagentWrites(for: id) == [])
    }

    @Test("removeSubagent clears the ledger entry")
    func removeClears() {
        let app = AppState(); let id = UUID()
        app.createNewConversation(id: id, isSubagent: true)
        app.recordSubagentWrite(conversationId: id, path: "a.swift")
        app.removeSubagent(id: id)
        #expect(app.drainSubagentWrites(for: id) == [])
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter SubagentWriteLedgerTests`
Expected: FAIL — `subagentWriteLedger`, `recordSubagentWrite`, `drainSubagentWrites` don't exist.

- [ ] **Step 3: Implement the ledger**

In `AppState.swift`, add the stored property near `activeSubagents` (~L142):
```swift
    var subagentWriteLedger: [UUID: [String]] = [:]
```

Add methods near `registerSubagent`/`removeSubagent` (~L249):
```swift
    /// Records a successful write_file path for a subagent conversation (deduped). No-op for the
    /// main agent so its writes don't accumulate. Drained into SubagentResult.filesWritten at
    /// termination (spec §5).
    func recordSubagentWrite(conversationId: UUID, path: String) {
        guard conversations.first(where: { $0.id == conversationId })?.isSubagent == true else { return }
        var list = subagentWriteLedger[conversationId] ?? []
        if !list.contains(path) { list.append(path) }
        subagentWriteLedger[conversationId] = list
    }

    /// Returns the recorded writes for a conversation and clears the entry.
    func drainSubagentWrites(for conversationId: UUID) -> [String] {
        let list = subagentWriteLedger[conversationId] ?? []
        subagentWriteLedger[conversationId] = nil
        return list
    }
```

In `removeSubagent(id:)` (~L254), add the clear:
```swift
    func removeSubagent(id: UUID) {
        activeSubagents.removeAll(where: { $0.id == id })
        subagentWriteLedger[id] = nil
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter SubagentWriteLedgerTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/iris/AppState.swift Tests/irisTests/SubagentWriteLedgerTests.swift
git commit -m "feat(subagent): per-conversation write_file ledger on AppState (slice B2, #13)"
```

---

### Task 3: Assemble the structured result through `SubagentManager`

**Files:**
- Modify: `Sources/iris/AppState.swift` (`onSubagentComplete` type ~L147; add `setSubagentResult`)
- Modify: `Sources/iris/iris.swift` (three termination sites: ~L119, ~L679, ~L860; the background notification wrapper ~L822)
- Modify: `Sources/iris/SubagentManager.swift` (holder type, registered callback, injectable cap, timeout site, assembly, persist, render, return)
- Test: `Tests/irisTests/SubagentManagerTests.swift` (update three exact-equality assertions; add status-mapping tests)

**Interfaces:**
- Consumes: `SubagentResult`, `SubagentTermination`, `SubagentTerminalStatus`, `renderedForParent()` (Task 1); `drainSubagentWrites(for:)`, `removeSubagent(id:)` (Task 2).
- Produces:
  - `AppState.onSubagentComplete: [UUID: @Sendable (SubagentTermination) -> Void]`
  - `AppState.setSubagentResult(for conversationId: UUID, _ result: SubagentResult)`
  - `SubagentManager.runSubagent(role:task:effort:parentConversationId:maxIterations:)` returns `renderedForParent()` prose; `maxIterations` defaults to `3000`.

- [ ] **Step 1: Write / update the failing tests**

In `Tests/irisTests/SubagentManagerTests.swift`:

Update the three existing exact-equality assertions (the return is now prose, not the raw summary):
- `testSubagentExecutionBlocksAndReturnsSummary` — replace `XCTAssertEqual(summary, "I have audited the code securely.")` with:
```swift
        XCTAssertTrue(summary.contains("I have audited the code securely."))
        XCTAssertTrue(summary.contains("status: completed"))
        XCTAssertTrue(summary.contains("goal_complete called"))
```
- `testConcurrentSubagentExecution` — replace `XCTAssertEqual(res, "Concurrent execution complete.")` with `XCTAssertTrue(res.contains("Concurrent execution complete."))`.
- `testInvalidEffortStringDefaultsToMedium` — replace `XCTAssertEqual(summary, "Finished with unknown effort.")` with `XCTAssertTrue(summary.contains("Finished with unknown effort."))`.

(`testNilStateReturnsError` is unchanged — the nil-state guard returns its error string before any result assembly.)

Add a timeout-mapping test (mock never calls `goal_complete`, so the poll cap fires):
```swift
    func testNeverCompletingSubagentTimesOut() async throws {
        let state = AppState()
        SubagentManager.shared.setGlobalState(state)

        // Always return plain text — the subagent never calls goal_complete, so it loops until the cap.
        MockURLProtocol.handler = { request in
            let responseJson: [String: Any] = [
                "id": UUID().uuidString, "type": "message", "role": "assistant",
                "model": "claude-3-5-sonnet",
                "content": [["type": "text", "text": "Still working..."]],
                "usage": ["input_tokens": 10, "output_tokens": 10]
            ]
            let data = try! JSONSerialization.data(withJSONObject: responseJson)
            let resp = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, data)
        }

        let parentId = UUID()
        await MainActor.run { state.createNewConversation(id: parentId) }

        let summary = await SubagentManager.shared.runSubagent(
            role: "worker", task: "loop forever", effort: "easy",
            parentConversationId: parentId, maxIterations: 3)   // ~300ms cap

        XCTAssertTrue(summary.contains("status: timed out"))
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter SubagentManagerTests`
Expected: FAIL — `maxIterations:` is not a parameter; the return is still the raw summary, so `contains("status: completed")` fails.

- [ ] **Step 3: Change the callback type and add the setter**

In `AppState.swift`, change the callback type (~L147):
```swift
    var onSubagentComplete: [UUID: @Sendable (SubagentTermination) -> Void] = [:]
```

Add near the other conversation helpers:
```swift
    /// Persists a subagent's structured result on its conversation for the UI and later slices.
    func setSubagentResult(for conversationId: UUID, _ result: SubagentResult) {
        guard let idx = conversations.firstIndex(where: { $0.id == conversationId }) else { return }
        conversations[idx].subagentResult = result
        saveConversations()
    }
```

- [ ] **Step 4: Update the three termination sites in `iris.swift`**

At the `goal_complete` site (~L860), change the callback invocation:
```swift
                localState?.onSubagentComplete[conversationId]?(SubagentTermination(status: .completed, summary: summary, calledGoalComplete: true))
```

At the LLM-error site (~L679):
```swift
                    localState?.onSubagentComplete[conversationId]?(SubagentTermination(status: .failed, summary: "Subagent failed due to LLM Error: \(error.localizedDescription)", calledGoalComplete: false))
```

At the stop/cancel site (~L119):
```swift
                localState?.onSubagentComplete[conversationId]?(SubagentTermination(status: .cancelled, summary: "Stopped: \(reason) (no explicit summary produced).", calledGoalComplete: false))
```

> The bare-string summaries these sites previously passed become the `summary` field. No other logic at these sites changes.

- [ ] **Step 5: Assemble the result in `SubagentManager`**

In `SubagentManager.swift`, change `runSubagent` (add `maxIterations` param; capture start time; hold a `SubagentTermination`; assemble on exit).

Signature:
```swift
    func runSubagent(role: String, task: String, effort: String, parentConversationId: UUID, maxIterations: Int = 3000) async -> String {
```

After the nil-state guard, capture the start time:
```swift
        let startedAt = Date()
```

Change the `ResultHolder` actor to hold a `SubagentTermination`:
```swift
        actor ResultHolder {
            var termination: SubagentTermination? = nil
            func set(_ t: SubagentTermination) { if termination == nil { termination = t } }
            func get() -> SubagentTermination? { return termination }
        }
        let holder = ResultHolder()
```

Change the registered callback:
```swift
        await MainActor.run {
            appState.onSubagentComplete[subagentId] = { termination in
                Task { await holder.set(termination) }
                Task { @MainActor in appState.onSubagentComplete[subagentId] = nil }
            }
        }
```

In the poll loop, replace `while await holder.getSummary() == nil` with `while await holder.get() == nil`, use the passed `maxIterations`, and set a `.timedOut` termination at the cap:
```swift
        var iterations = 0
        while await holder.get() == nil {
            if iterations >= maxIterations {
                engineTask.cancel()
                await MainActor.run { appState.denyPendingApprovals(for: subagentId) }
                await engine.cancelReprompt(for: subagentId)
                await SandboxSessionManager.shared.endSession(subagentId)
                await MainActor.run { appState.clearGoal(for: subagentId) }
                await holder.set(SubagentTermination(status: .timedOut,
                    summary: "Subagent timed out after the iteration cap and was cancelled (task, pending approvals, and sandbox container cleaned up).",
                    calledGoalComplete: false))
                break
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
            iterations += 1
        }
```

Replace the final summary/return block with assembly:
```swift
        let termination = await holder.get() ?? SubagentTermination(status: .failed, summary: "Subagent completed with no summary.", calledGoalComplete: false)
        let files = await MainActor.run { appState.drainSubagentWrites(for: subagentId) }
        let result = SubagentResult(role: role, status: termination.status,
                                    calledGoalComplete: termination.calledGoalComplete,
                                    summary: termination.summary, filesWritten: files,
                                    startedAt: startedAt, endedAt: Date())
        await MainActor.run {
            appState.setSubagentResult(for: subagentId, result)
            appState.removeSubagent(id: subagentId)
        }
        return result.renderedForParent()
```

- [ ] **Step 6: Keep the background notification consistent**

In `iris.swift` (~L822), the background `invoke_subagent` branch already awaits `runSubagent` and posts a System Event. Since `runSubagent` now returns rendered prose (which already names the role and status), simplify the wrapper so it isn't doubly prefixed:
```swift
                Task {
                    let rendered = await SubagentManager.shared.runSubagent(role: role, task: task, effort: effort, parentConversationId: conversationId)
                    await self.handleSystemEvent("Background subagent result:\n\(rendered)", source: "SubagentManager", conversationId: conversationId)
                }
```

- [ ] **Step 7: Run the tests to verify they pass**

Run: `swift test --filter SubagentManagerTests`
Expected: PASS (existing tests updated + the new timeout test).

- [ ] **Step 8: Run the goal suite to confirm no regression**

Run: `swift test --filter Goal`
Expected: PASS — main-agent `goal_complete` is unchanged (no `onSubagentComplete` registered for the main agent, so the new termination call is a no-op there).

- [ ] **Step 9: Commit**

```bash
git add Sources/iris/AppState.swift Sources/iris/iris.swift Sources/iris/SubagentManager.swift Tests/irisTests/SubagentManagerTests.swift
git commit -m "feat(subagent): assemble structured result through SubagentManager (slice B2, #13)"
```

---

### Task 4: Wire the write-ledger recording hook

**Files:**
- Modify: `Sources/iris/iris.swift` (`executeToolWithHooks`, right after `executor.execute` returns ~L985)
- Test: `Tests/irisTests/SubagentManagerTests.swift` (add an end-to-end files-written test)

**Interfaces:**
- Consumes: `AppState.recordSubagentWrite(conversationId:path:)` (Task 2); `ToolExecutor.resolvePath(_:cwd:)` (existing static); `PermissionManager.shared.allowGlobally(toolName:details:)` (existing, for the test fast-path).
- Produces: a side-record of resolved `write_file` paths into the ledger on success.

- [ ] **Step 1: Write the failing test**

Add to `SubagentManagerTests` an e2e where the subagent writes a file then completes. Pre-seed the permission so `write_file` auto-approves (the `isAllowed` fast path), and drive two mocked turns:

```swift
    func testSubagentWriteIsRecordedInResult() async throws {
        let state = AppState()
        SubagentManager.shared.setGlobalState(state)
        // Fast-path approve write_file for the exact path the mock uses (spec §5 / requestApproval).
        PermissionManager.shared.allowGlobally(toolName: "write_file", details: "ledger_probe.txt")

        let lock = NSLock(); var count = 0
        MockURLProtocol.handler = { request in
            lock.lock(); let c = count; count += 1; lock.unlock()
            let input: [String: Any]
            if c == 0 {
                input = ["type": "tool_use", "id": "w1", "name": "write_file",
                         "input": ["path": "ledger_probe.txt", "content": "hi"]]
            } else {
                input = ["type": "tool_use", "id": "g1", "name": "goal_complete",
                         "input": ["summary": "wrote the file"]]
            }
            let responseJson: [String: Any] = [
                "id": UUID().uuidString, "type": "message", "role": "assistant",
                "model": "claude-3-5-sonnet", "content": [input],
                "usage": ["input_tokens": 10, "output_tokens": 10]
            ]
            let data = try! JSONSerialization.data(withJSONObject: responseJson)
            let resp = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (resp, data)
        }

        let parentId = UUID()
        await MainActor.run { state.createNewConversation(id: parentId) }
        let summary = await SubagentManager.shared.runSubagent(
            role: "engineer", task: "write a file", effort: "easy", parentConversationId: parentId)

        XCTAssertTrue(summary.contains("Files written (1)"))
        XCTAssertTrue(summary.contains("ledger_probe.txt"))
    }
```

> The subagent runs against the process working directory (no bound workspace), so `ledger_probe.txt` is created there; delete it at the end of the test if present. The global permission rule for `write_file`/`ledger_probe.txt` is a benign throwaway.

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter testSubagentWriteIsRecordedInResult`
Expected: FAIL — nothing records the write, so `filesWritten` is empty and the prose omits the files line.

- [ ] **Step 3: Add the recording hook**

In `iris.swift`, in `executeToolWithHooks`, immediately after `var result = await executor.execute(...)` (~L985), before the `fireAfterTool` block:
```swift
        if name == "write_file", result.hasPrefix("Successfully wrote to "),
           let cid = conversationId, let path = execArgs["path"]?.stringValue {
            let resolved = ToolExecutor.resolvePath(path, cwd: cwd)
            await MainActor.run { localState?.recordSubagentWrite(conversationId: cid, path: resolved) }
        }
```

> `recordSubagentWrite` no-ops for non-subagent conversations, so this is inert for the main agent. `resolvePath` matches the path `writeFile` actually wrote to.

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --filter testSubagentWriteIsRecordedInResult`
Expected: PASS.

- [ ] **Step 5: Run the full subagent suite**

Run: `swift test --filter SubagentManagerTests`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/iris/iris.swift Tests/irisTests/SubagentManagerTests.swift
git commit -m "feat(subagent): record write_file paths into the ledger on success (slice B2, #13)"
```

---

### Task 5: Docs — mark the slice implemented

**Files:**
- Modify: `docs/specs/2026-08-02-subagent-structured-result.md`

- [ ] **Step 1: Update the status**

Change `Status` from `Approved (design)` to `Implemented`. Confirm §10 still names B3 (bounded-unit contract) as the next slice. Per the repo's atomic Definition-of-Done rule, docs update in the same branch as the feature.

- [ ] **Step 2: Commit**

```bash
git add docs/specs/2026-08-02-subagent-structured-result.md
git commit -m "docs(subagent): mark structured inner-loop result (slice B2) implemented (#13)"
```

---

## Self-Review

**Spec coverage:**
- §1/§2 overview + scope → Tasks 1-4 collectively; deferred items (B3/B4, no run_command tracking) are enforced by not building them.
- §3 data model (types, fields, `decodeIfPresent`, memory-guarded backwards compat) → Task 1.
- §4 four termination sites + centralized assembly + main-agent no-op → Task 3.
- §5 files-written ledger (subagent-only, write_file-only, drained at termination) → Task 2 (mechanics) + Task 4 (recording hook).
- §6 prose to the parent + background variant consistency → Task 1 (`renderedForParent`) + Task 3 steps 5-6.
- §7 edge cases (timeout/failed/cancelled partial files, empty files, legacy decode) → Task 1 (legacy decode, empty-files render), Task 3 (timeout mapping), Task 2 (subagent scoping).
- §8 testing → Task 1 (Codable + rendering + legacy), Task 2 (ledger), Task 3 (status mapping + regression), Task 4 (e2e files-written).
- §9 fixed constraints (goal_complete, ladder, evaluator, ToolExecutor shape) → untouched by construction; Task 3 step 8 regression run guards `goal_complete`.

**Placeholder scan:** every code step carries real code; no TBD/TODO. The `.cancelled` status is exercised at the render level (Task 1) rather than via a fragile mid-run-cancel integration test — a deliberate, stated choice, not an omission (its site is wired in Task 3 step 4).

**Type consistency:** `SubagentTerminalStatus`, `SubagentTermination`, `SubagentResult`, `renderedForParent()`, `subagentResult`, `recordSubagentWrite(conversationId:path:)`, `drainSubagentWrites(for:)`, `setSubagentResult(for:_:)`, `onSubagentComplete: [UUID: @Sendable (SubagentTermination) -> Void]`, `runSubagent(...maxIterations:)` — names used identically across Tasks 1-4.
