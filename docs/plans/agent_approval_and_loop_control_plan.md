# Agent Approval & Loop-Control Overhaul — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the subagent-approval hang and runaway goal loops: queue approvals with origin labels, add a Vibecop timeout + sandbox-aware verdicts, and give every goal loop a configurable cap, loop detection, graceful summaries, and real subagent cancellation.

**Architecture:** Pure, unit-tested helpers (`LoopDetector`, `withTimeout`) plus surgical wiring in `AppState` (approval queue), `VibecopService` (timeout + sandbox context), `IrisEngine` (routing, loop control, summarize), and `SubagentManager` (task cancellation + teardown).

**Tech Stack:** Swift, Swift Concurrency (actors, task groups, continuations), SwiftUI, Swift Testing (`import Testing`, `@Test`, `#expect`).

## Global Constraints

- Defaults: `maxGoalIterations = 50`, `loopDetectionThreshold = 5`, `vibecopTimeoutSeconds = 5`. All three are `ConfigManager` settings.
- The approval queue is FIFO; `resolveApproval` resolves the **head**. `AppState` is `@MainActor`; all queue mutations and continuation resumes happen on the main actor. A continuation is resumed exactly once.
- Loop signatures MUST be deterministic: `"<toolName>|<args-as-sorted-keys-JSON>"` (`JSONEncoder().outputFormatting = [.sortedKeys]`).
- Vibecop timeout fails **open to the user prompt** (ESCALATE); it never throws-to-block or hangs the turn.
- On any goal-loop stop, the agent hands back a summary — soft stop (cap/loop, agent responsive) via a final `goal_complete`-with-summary turn; hard stop (timeout/cancel) via a deterministic string (no LLM call). Messages are principal-correct (never "Subagent failed" for the main agent).
- Subagent teardown order on timeout/cancel: cancel task → `denyPendingApprovals(for:)` → `cancelReprompt` → `SandboxSessionManager.endSession` → `clearGoal` → return deterministic summary.
- The `6935d8b` bypass (`needsApproval && !useSandbox`) is reverted to `needsApproval`.
- New tests use Swift Testing, matching `Tests/irisTests/SandboxPolicyTests.swift`.

---

### Task 1: `LoopDetector` (deterministic signatures + repetition detection)

**Files:**
- Create: `Sources/iris/LoopDetector.swift`
- Test: `Tests/irisTests/LoopDetectorTests.swift`

**Interfaces:**
- Produces:
  - `static func LoopDetector.signature(toolName: String, args: [String: JSONValue]) -> String`
  - `struct LoopDetector { init(threshold: Int); mutating func record(_ signature: String) -> Bool; mutating func reset() }` — `record` returns `true` when the last `threshold` signatures are identical.

- [ ] **Step 1: Write the failing tests**

Create `Tests/irisTests/LoopDetectorTests.swift`:

```swift
import Testing
import Foundation
@testable import iris

@Suite("LoopDetector")
struct LoopDetectorTests {
    @Test("signature is deterministic regardless of arg insertion order")
    func deterministicSignature() {
        let a: [String: JSONValue] = ["path": .string("/x"), "mode": .string("r")]
        let b: [String: JSONValue] = ["mode": .string("r"), "path": .string("/x")]
        #expect(LoopDetector.signature(toolName: "read_file", args: a)
                == LoopDetector.signature(toolName: "read_file", args: b))
    }

    @Test("different tool or args produce different signatures")
    func distinctSignatures() {
        let s1 = LoopDetector.signature(toolName: "run_command", args: ["command": .string("ls")])
        let s2 = LoopDetector.signature(toolName: "run_command", args: ["command": .string("pwd")])
        let s3 = LoopDetector.signature(toolName: "read_file", args: ["command": .string("ls")])
        #expect(s1 != s2)
        #expect(s1 != s3)
    }

    @Test("record trips only after threshold identical signatures")
    func tripsAtThreshold() {
        var d = LoopDetector(threshold: 3)
        #expect(d.record("a") == false)
        #expect(d.record("a") == false)
        #expect(d.record("a") == true)   // 3rd identical → loop
    }

    @Test("a differing signature resets the run")
    func resets() {
        var d = LoopDetector(threshold: 3)
        _ = d.record("a"); _ = d.record("a")
        #expect(d.record("b") == false)  // reset
        #expect(d.record("b") == false)
        #expect(d.record("b") == true)
    }

    @Test("reset() clears history")
    func explicitReset() {
        var d = LoopDetector(threshold: 2)
        _ = d.record("a")
        d.reset()
        #expect(d.record("a") == false)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter LoopDetector`
Expected: FAIL — `cannot find 'LoopDetector' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Sources/iris/LoopDetector.swift`:

```swift
import Foundation

/// Detects an agent stuck repeating the same tool call. Signatures are canonical so identical
/// arguments always compare equal regardless of dictionary ordering.
struct LoopDetector {
    private let threshold: Int
    private var recent: [String] = []

    init(threshold: Int) {
        self.threshold = max(2, threshold)
    }

    /// A stable signature for a tool call: name + args serialized with sorted keys.
    static func signature(toolName: String, args: [String: JSONValue]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let argsString: String
        if let data = try? encoder.encode(args), let s = String(data: data, encoding: .utf8) {
            argsString = s
        } else {
            argsString = "\(args)"   // fallback; still stable within a process for equal inputs
        }
        return "\(toolName)|\(argsString)"
    }

    /// Records a signature; returns true when the last `threshold` signatures are identical.
    mutating func record(_ signature: String) -> Bool {
        if recent.last != signature { recent.removeAll() }
        recent.append(signature)
        if recent.count > threshold { recent.removeFirst(recent.count - threshold) }
        return recent.count >= threshold && recent.allSatisfy { $0 == signature }
    }

    mutating func reset() { recent.removeAll() }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter LoopDetector`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/iris/LoopDetector.swift Tests/irisTests/LoopDetectorTests.swift
git commit -m "feat(agent): LoopDetector — deterministic signatures + repetition detection"
```

---

### Task 2: `withTimeout` generic helper

**Files:**
- Create: `Sources/iris/Timeout.swift`
- Test: `Tests/irisTests/TimeoutTests.swift`

**Interfaces:**
- Produces:
  - `struct TimeoutError: Error, Equatable {}`
  - `func withTimeout<T: Sendable>(seconds: Double, _ operation: @escaping @Sendable () async throws -> T) async throws -> T` — throws `TimeoutError` if `operation` doesn't finish in time; cancels the losing branch.

- [ ] **Step 1: Write the failing tests**

Create `Tests/irisTests/TimeoutTests.swift`:

```swift
import Testing
import Foundation
@testable import iris

@Suite("withTimeout")
struct TimeoutTests {
    @Test("fast operation returns its value")
    func fastReturns() async throws {
        let v = try await withTimeout(seconds: 2) { () -> Int in 42 }
        #expect(v == 42)
    }

    @Test("slow operation throws TimeoutError")
    func slowThrows() async {
        await #expect(throws: TimeoutError.self) {
            try await withTimeout(seconds: 0.05) { () -> Int in
                try await Task.sleep(nanoseconds: 2_000_000_000)
                return 1
            }
        }
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter withTimeout`
Expected: FAIL — `cannot find 'withTimeout' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Sources/iris/Timeout.swift`:

```swift
import Foundation

struct TimeoutError: Error, Equatable {}

/// Runs `operation` with a wall-clock timeout. If it doesn't finish in `seconds`, throws
/// `TimeoutError` and cancels the operation (best-effort — a non-cooperative call may still run
/// to completion in the background, but its result is discarded).
func withTimeout<T: Sendable>(seconds: Double, _ operation: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw TimeoutError()
        }
        defer { group.cancelAll() }
        let result = try await group.next()!
        return result
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter withTimeout`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/iris/Timeout.swift Tests/irisTests/TimeoutTests.swift
git commit -m "feat(agent): withTimeout helper (fail-open timeout wrapper)"
```

---

### Task 3: Config knobs

**Files:**
- Modify: `Sources/iris/ConfigManager.swift`

**Interfaces:**
- Produces: `ConfigManager.maxGoalIterations: Int` (default 50, key `MAX_GOAL_ITERATIONS`), `loopDetectionThreshold: Int` (default 5, key `LOOP_DETECTION_THRESHOLD`), `vibecopTimeoutSeconds: Int` (default 5, key `VIBECOP_TIMEOUT_SECONDS`).

- [ ] **Step 1: Add the properties**

After the `vibecopModel` property block in `ConfigManager.swift`, add:

```swift
    var maxGoalIterations: Int {
        didSet { UserDefaults.standard.set(maxGoalIterations, forKey: "MAX_GOAL_ITERATIONS") }
    }
    var loopDetectionThreshold: Int {
        didSet { UserDefaults.standard.set(loopDetectionThreshold, forKey: "LOOP_DETECTION_THRESHOLD") }
    }
    var vibecopTimeoutSeconds: Int {
        didSet { UserDefaults.standard.set(vibecopTimeoutSeconds, forKey: "VIBECOP_TIMEOUT_SECONDS") }
    }
```

- [ ] **Step 2: Initialize them**

In `ConfigManager.init`, after the vibecop settings are read, add (each maps the UserDefaults "0 when unset" to its default):

```swift
        let savedMaxIters = UserDefaults.standard.integer(forKey: "MAX_GOAL_ITERATIONS")
        self.maxGoalIterations = savedMaxIters == 0 ? 50 : savedMaxIters
        let savedLoop = UserDefaults.standard.integer(forKey: "LOOP_DETECTION_THRESHOLD")
        self.loopDetectionThreshold = savedLoop == 0 ? 5 : savedLoop
        let savedVibecopTO = UserDefaults.standard.integer(forKey: "VIBECOP_TIMEOUT_SECONDS")
        self.vibecopTimeoutSeconds = savedVibecopTO == 0 ? 5 : savedVibecopTO
```

- [ ] **Step 3: Build**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 4: Commit**

```bash
git add Sources/iris/ConfigManager.swift
git commit -m "feat(agent): config for goal cap, loop threshold, vibecop timeout"
```

---

### Task 4: Approval queue on `AppState`

**Files:**
- Modify: `Sources/iris/AppState.swift`
- Test: `Tests/irisTests/ApprovalQueueTests.swift`

**Interfaces:**
- Consumes: nothing new.
- Produces:
  - `ToolApprovalRequest` gains `let conversationId: UUID?` and `let origin: String`.
  - `AppState.pendingApprovals: [ToolApprovalRequest]` (replaces `pendingApproval`).
  - `AppState.enqueueUserApproval(toolName:details:workspace:conversationId:origin:) async -> Bool` — appends a request and awaits its continuation (the testable seam).
  - `AppState.resolveApproval(_:)` — resolves the **head** request, applies permission persistence, pops it.
  - `AppState.denyPendingApprovals(for conversationId: UUID)` — resolves-false and removes all requests for that conversation.

- [ ] **Step 1: Write the failing tests**

Create `Tests/irisTests/ApprovalQueueTests.swift`:

```swift
import Testing
import Foundation
@testable import iris

@MainActor
@Suite("Approval queue")
struct ApprovalQueueTests {
    @Test("resolveApproval resolves the FIFO head; deny then approve")
    func fifoResolve() async {
        let app = AppState()
        let cid = UUID()
        async let r1 = app.enqueueUserApproval(toolName: "run_command", details: "a", workspace: nil, conversationId: cid, origin: "Main agent")
        async let r2 = app.enqueueUserApproval(toolName: "run_command", details: "b", workspace: nil, conversationId: cid, origin: "Main agent")
        // Let both enqueue.
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(app.pendingApprovals.count == 2)
        app.resolveApproval(.deny)     // head (a) denied
        app.resolveApproval(.approve)  // next (b) approved
        let v1 = await r1
        let v2 = await r2
        #expect(v1 == false)
        #expect(v2 == true)
        #expect(app.pendingApprovals.isEmpty)
    }

    @Test("denyPendingApprovals denies only the matching conversation")
    func denyByConversation() async {
        let app = AppState()
        let a = UUID(); let b = UUID()
        async let ra = app.enqueueUserApproval(toolName: "t", details: "a", workspace: nil, conversationId: a, origin: "Subagent (x)")
        async let rb = app.enqueueUserApproval(toolName: "t", details: "b", workspace: nil, conversationId: b, origin: "Main agent")
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(app.pendingApprovals.count == 2)
        app.denyPendingApprovals(for: a)
        let va = await ra
        #expect(va == false)
        #expect(app.pendingApprovals.count == 1)
        #expect(app.pendingApprovals.first?.conversationId == b)
        app.resolveApproval(.approve)
        let vb = await rb
        #expect(vb == true)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter "Approval queue"`
Expected: FAIL — `enqueueUserApproval` / `pendingApprovals` not found.

- [ ] **Step 3: Implement**

In `AppState.swift`, change `ToolApprovalRequest`:

```swift
struct ToolApprovalRequest: Identifiable {
    let id = UUID()
    let toolName: String
    let details: String
    let workspace: String?
    let conversationId: UUID?
    let origin: String
    let continuation: CheckedContinuation<Bool, Never>
}
```

Replace the property `var pendingApproval: ToolApprovalRequest?` with:

```swift
    var pendingApprovals: [ToolApprovalRequest] = []
```

Add the enqueue seam and update resolve/deny. Add near `requestApproval`:

```swift
    /// Appends an approval request and awaits the user's decision. The queue/continuation seam,
    /// separated from `requestApproval`'s permission/Vibecop fast paths so it is unit-testable.
    func enqueueUserApproval(toolName: String, details: String, workspace: String?,
                             conversationId: UUID?, origin: String) async -> Bool {
        await withCheckedContinuation { continuation in
            pendingApprovals.append(ToolApprovalRequest(
                toolName: toolName, details: details, workspace: workspace,
                conversationId: conversationId, origin: origin, continuation: continuation))
        }
    }

    /// Resolves-false and removes every queued request for a conversation. Used to unstick a
    /// subagent blocked on approval when it is cancelled/timed-out.
    func denyPendingApprovals(for conversationId: UUID) {
        let matching = pendingApprovals.filter { $0.conversationId == conversationId }
        pendingApprovals.removeAll { $0.conversationId == conversationId }
        for req in matching { req.continuation.resume(returning: false) }
    }
```

Change `resolveApproval` to operate on the head of the queue (replace `pendingApproval` references):

```swift
    func resolveApproval(_ resolution: ApprovalResolution) {
        guard !pendingApprovals.isEmpty else { return }
        let pending = pendingApprovals.removeFirst()
        var approved = false
        switch resolution {
        case .approve:
            approved = true
        case .deny:
            approved = false
        case .alwaysAllowGlobal:
            PermissionManager.shared.allowGlobally(toolName: pending.toolName, details: pending.details)
            approved = true
        case .alwaysAllowProject:
            if let workspace = pending.workspace {
                PermissionManager.shared.allowInProject(toolName: pending.toolName, details: pending.details, workspace: workspace)
            } else {
                PermissionManager.shared.allowGlobally(toolName: pending.toolName, details: pending.details)
            }
            approved = true
        }
        pending.continuation.resume(returning: approved)
    }
```

(Do NOT change `requestApproval` yet — Task 5 rewires it to call `enqueueUserApproval`. Temporarily, keep `requestApproval`'s existing body but change its final `withCheckedContinuation { … self.pendingApproval = … }` to `return await enqueueUserApproval(toolName: toolName, details: details, workspace: workspace, conversationId: nil, origin: "Main agent")` so the project compiles; Task 5 adds the real params.)

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter "Approval queue"`
Expected: PASS (2 tests).

- [ ] **Step 5: Build (whole project compiles with the temporary shim)**

Run: `swift build`
Expected: `Build complete!` (the ChatView banner still references `pendingApproval` — if so, Task 6 fixes it; to keep this task self-contained, update the two `ChatView.swift` references from `state.pendingApproval` to `state.pendingApprovals.first` now, matching Task 6 Step 1's binding).

- [ ] **Step 6: Commit**

```bash
git add Sources/iris/AppState.swift Sources/iris/ChatView.swift Tests/irisTests/ApprovalQueueTests.swift
git commit -m "feat(agent): FIFO approval queue with per-conversation deny"
```

---

### Task 5: `requestApproval` → permission → Vibecop(timeout, sandbox-aware) → enqueue

**Files:**
- Modify: `Sources/iris/AppState.swift` (`requestApproval`)
- Modify: `Sources/iris/VibecopService.swift` (`evaluateAction`)

**Interfaces:**
- Consumes: `withTimeout` (Task 2); `enqueueUserApproval` (Task 4); `ConfigManager.vibecopTimeoutSeconds` (Task 3).
- Produces:
  - `VibecopService.evaluateAction(toolName:details:workspace:inSandbox:)` — new `inSandbox: Bool = false` param.
  - `AppState.requestApproval(toolName:details:workspace:conversationId:origin:inSandbox:) async -> Bool`.

- [ ] **Step 1: Make Vibecop sandbox-aware**

In `VibecopService.swift`, change the signature and add sandbox context to the prompt:

```swift
    func evaluateAction(toolName: String, details: String, workspace: String?, inSandbox: Bool = false) async throws -> VibecopDecision {
```

Immediately before the `prompt += "\n\nProposed Action:..."` line, add:

```swift
        if inSandbox {
            prompt += """


            EXECUTION CONTEXT: This command runs inside a disposable, network-capable Linux VM
            fully isolated from the macOS host filesystem. Auto-APPROVE routine in-VM work
            (building, testing, inspecting files, installing packages). Reserve ESCALATE/DENY for
            genuinely risky actions: outbound network connections to new/unknown hosts, attempts
            to escape the container or escalate privilege, or reaching host-bridged resources.
            """
        }
```

- [ ] **Step 2: Rewrite `requestApproval` with the timeout + params**

Replace `requestApproval` in `AppState.swift`:

```swift
    func requestApproval(toolName: String, details: String, workspace: String? = nil,
                         conversationId: UUID? = nil, origin: String = "Main agent",
                         inSandbox: Bool = false) async -> Bool {
        // Fast path: deterministic permissions.
        if PermissionManager.shared.isAllowed(toolName: toolName, details: details, workspace: workspace) {
            return true
        }

        // Vibecop, bounded by a timeout so a wedged local model can't hang the turn.
        do {
            let timeout = Double(ConfigManager.shared.vibecopTimeoutSeconds)
            let decision = try await withTimeout(seconds: timeout) {
                try await VibecopService.shared.evaluateAction(toolName: toolName, details: details, workspace: workspace, inSandbox: inSandbox)
            }
            if decision.decision == "APPROVE" { return true }
            if decision.decision == "DENY" { return false }
            // ESCALATE → fall through to the user prompt.
        } catch {
            // Timeout or Vibecop error → fail open to the user prompt.
            print("Vibecop evaluation failed/timed out: \(error)")
        }

        return await enqueueUserApproval(toolName: toolName, details: details, workspace: workspace,
                                         conversationId: conversationId, origin: origin)
    }
```

- [ ] **Step 3: Build**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 4: Run the approval-queue tests (unaffected)**

Run: `swift test --filter "Approval queue"`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/iris/AppState.swift Sources/iris/VibecopService.swift
git commit -m "feat(agent): bounded sandbox-aware Vibecop; requestApproval enqueues with origin"
```

---

### Task 6: Approval banner — origin label + queue depth

**Files:**
- Modify: `Sources/iris/ChatView.swift`

**Interfaces:**
- Consumes: `AppState.pendingApprovals`, `ToolApprovalRequest.origin` (Tasks 4).

- [ ] **Step 1: Point the banner at the queue head**

In `ChatView.swift`, replace the banner block (currently `if let request = state.pendingApproval { ApprovalBannerView(request:…) … .animation(…, value: state.pendingApproval != nil) }`) with:

```swift
                    if let request = state.pendingApprovals.first {
                        ApprovalBannerView(request: request,
                                           queueDepth: state.pendingApprovals.count,
                                           onResolve: { resolution in
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                state.resolveApproval(resolution)
                            }
                        })
                        .padding(.horizontal)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: state.pendingApprovals.count)
                    }
```

- [ ] **Step 2: Show origin + "N more pending" in the banner**

In `ApprovalBannerView`, add `let queueDepth: Int` and use `request.origin`. Replace the header/subtitle region:

```swift
struct ApprovalBannerView: View {
    let request: ToolApprovalRequest
    let queueDepth: Int
    let onResolve: (AppState.ApprovalResolution) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "exclamationmark.shield.fill")
                    .foregroundColor(.orange)
                Text("Security Guard: Permission Required")
                    .font(.headline)
                Spacer()
                if queueDepth > 1 {
                    Text("\(queueDepth - 1) more pending")
                        .font(.caption).foregroundColor(.secondary)
                }
            }

            Text("\(request.origin) wants to run a potentially sensitive action:")
                .font(.subheadline)

            Text("\(request.toolName): \(request.details)")
                .font(.caption.monospaced())
                .padding(8)
                .background(Color.black.opacity(0.1))
                .cornerRadius(4)
            // ...existing buttons unchanged...
```

(Leave the existing button `HStack` and the rest of the view as-is.)

- [ ] **Step 3: Build**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 4: Commit**

```bash
git add Sources/iris/ChatView.swift
git commit -m "feat(agent): approval banner shows origin + queue depth"
```

---

### Task 7: Engine approval wiring — revert bypass, thread origin + inSandbox

**Files:**
- Modify: `Sources/iris/iris.swift` (`IrisEngine`: `roleLabel`, `executeFunctionCall` approval call)
- Modify: `Sources/iris/SubagentManager.swift` (pass `roleLabel`)

**Interfaces:**
- Consumes: `requestApproval(...conversationId:origin:inSandbox:)` (Task 5).
- Produces: `IrisEngine.roleLabel: String?`.

- [ ] **Step 1: Add `roleLabel` to `IrisEngine`**

Add a stored property near `principal`:

```swift
    let roleLabel: String?
```

Update `init` (keep existing params, add `roleLabel`):

```swift
    init(state: AppState, tier: ModelTier = .medium, principal: Principal = .main, roleLabel: String? = nil) {
        self.state = state
        self.modelTier = tier
        self.principal = principal
        self.roleLabel = roleLabel
        systemPrompt = nil
    }
```

Add a computed origin string near the sandbox helpers:

```swift
    private var approvalOrigin: String {
        switch principal {
        case .main: return "Main agent"
        case .subagent: return "Subagent (\(roleLabel ?? "subagent"))"
        }
    }
```

- [ ] **Step 2: Revert the bypass and thread origin + inSandbox**

In `executeFunctionCall`, change the approval gate (currently `if needsApproval && !useSandbox {`) and the `requestApproval` call:

```swift
            if needsApproval {
                let approved = await localState?.requestApproval(
                    toolName: functionCall.name, details: details, workspace: workspacePath,
                    conversationId: conversationId, origin: approvalOrigin, inSandbox: useSandbox) ?? false
```

- [ ] **Step 3: Pass `roleLabel` from `SubagentManager`**

In `SubagentManager.swift`, change the engine construction:

```swift
        let engine = IrisEngine(state: appState, tier: tier, principal: .subagent, roleLabel: role)
```

- [ ] **Step 4: Build**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 5: Commit**

```bash
git add Sources/iris/iris.swift Sources/iris/SubagentManager.swift
git commit -m "feat(agent): revert sandboxed-approval bypass; label approvals by principal/role"
```

---

### Task 8: Loop control — cap, detection, summarize + hand back

**Files:**
- Modify: `Sources/iris/iris.swift`

**Interfaces:**
- Consumes: `LoopDetector` (Task 1); `ConfigManager.maxGoalIterations`, `.loopDetectionThreshold` (Task 3).

**Note:** Wiring/behavioral — verified by build (the pure loop logic is already unit-tested in Task 1). This replaces the hardcoded `> 100` force-complete with a configurable cap, adds loop detection, and routes both to a graceful summary.

- [ ] **Step 1: Add per-conversation loop detectors + a soft-stop helper**

Add a stored property to `IrisEngine`:

```swift
    private var loopDetectors: [UUID: LoopDetector] = [:]
```

Add a soft-stop helper (reuses the existing `goal_complete` routing by instructing the model to call it, then guaranteeing the goal is cleared so no reprompt):

```swift
    /// Graceful stop for a responsive-but-stuck goal loop: clear the reprompt, instruct the model
    /// to summarize and call goal_complete, and clear the goal so the loop cannot continue.
    private func softStopWithSummary(conversationId: UUID, reason: String) async {
        cancelReprompt(for: conversationId)
        loopDetectors[conversationId]?.reset()
        await pushToUI(role: .system, text: "[\(approvalOrigin)] \(reason) Summarizing and stopping.", conversationId: conversationId)
        await processInput(
            "You have reached a stopping condition (\(reason)). Summarize what you accomplished and what is blocking you, then call `goal_complete` with that summary. Do not take any other action.",
            source: "System", conversationId: conversationId)
        // Ensure the loop ends even if the model did not call goal_complete.
        let localState = state
        await MainActor.run {
            if localState?.conversations.first(where: { $0.id == conversationId })?.activeGoal != nil {
                localState?.clearGoal(for: conversationId)
                localState?.onSubagentComplete[conversationId]?("Stopped: \(reason) (no explicit summary produced).")
            }
        }
    }
```

- [ ] **Step 2: Detect loops after tool execution**

In `processInputBody`'s turn loop, after the tool calls for a turn have executed (where `toolCalls` is known and non-empty), record each executed call's signature and soft-stop on a trip. Add, right after the tool results are collected (before the loop continues):

```swift
                    // Loop detection: if the same tool call repeats too many times, stop early.
                    if await MainActor.run(body: { localState?.conversations.first(where: { $0.id == conversationId })?.activeGoal != nil }) {
                        let threshold = ConfigManager.shared.loopDetectionThreshold
                        var detector = loopDetectors[conversationId] ?? LoopDetector(threshold: threshold)
                        var tripped = false
                        for call in toolCalls {
                            if detector.record(LoopDetector.signature(toolName: call.name, args: call.args)) { tripped = true }
                        }
                        loopDetectors[conversationId] = detector
                        if tripped {
                            turnFinished = true
                            await softStopWithSummary(conversationId: conversationId, reason: "repeated the same action \(threshold)× in a row")
                            break
                        }
                    }
```

- [ ] **Step 3: Replace the hardcoded 100 cap with the configurable cap + summary**

In the auto-reprompt tail, replace the `if activeGoalResult.1 > 100 { … "Subagent failed…" … }` branch with:

```swift
        if let _ = activeGoalResult.0 {
            if activeGoalResult.1 >= ConfigManager.shared.maxGoalIterations {
                await softStopWithSummary(conversationId: conversationId,
                                          reason: "reached the \(ConfigManager.shared.maxGoalIterations)-iteration limit")
            } else {
                // ...existing auto-reprompt Task unchanged...
            }
        }
```

- [ ] **Step 4: Reset the detector on a new user turn**

At the top of `processInputBody`, when `source == "UI"`, reset the conversation's detector so a fresh instruction starts clean:

```swift
        if source == "UI" { loopDetectors[conversationId] = nil }
```

- [ ] **Step 5: Build**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 6: Commit**

```bash
git add Sources/iris/iris.swift
git commit -m "feat(agent): configurable goal cap + loop detection + summarize-and-handback"
```

---

### Task 9: Subagent task cancellation & teardown

**Files:**
- Modify: `Sources/iris/SubagentManager.swift`

**Interfaces:**
- Consumes: `AppState.denyPendingApprovals(for:)` (Task 4); `IrisEngine.cancelReprompt(for:)` (existing); `SandboxSessionManager.shared.endSession(_:)` (Piece 1); `AppState.clearGoal(for:)` (existing).

**Note:** Wiring — verified by build. Fixes the "subagent stuck forever" leak.

- [ ] **Step 1: Store the engine task and tear down on timeout**

In `runSubagent`, capture the kickoff `Task` and replace the timeout branch with a full teardown. Change:

```swift
        Task {
            await engine.processInput(task, source: "System", conversationId: subagentId)
        }
```

to:

```swift
        let engineTask = Task {
            await engine.processInput(task, source: "System", conversationId: subagentId)
        }
```

And change the timeout branch inside the wait loop:

```swift
            if iterations >= maxIterations {
                // Hard stop: cancel the engine task, unstick any pending approval, stop the
                // reprompt loop, free the sandbox container, and clear the goal.
                engineTask.cancel()
                await MainActor.run { appState.denyPendingApprovals(for: subagentId) }
                await engine.cancelReprompt(for: subagentId)
                await SandboxSessionManager.shared.endSession(subagentId)
                await MainActor.run { appState.clearGoal(for: subagentId) }
                await holder.setSummary("Subagent timed out after 5 minutes and was cancelled (task, pending approvals, and sandbox container cleaned up).")
                break
            }
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/iris/SubagentManager.swift
git commit -m "feat(agent): cancel + fully tear down timed-out subagents"
```

---

### Task 10: Settings — Agent limits

**Files:**
- Modify: `Sources/iris/SettingsView.swift`

**Interfaces:**
- Consumes: `ConfigManager.maxGoalIterations`, `.loopDetectionThreshold`, `.vibecopTimeoutSeconds` (Task 3).

- [ ] **Step 1: Add an "Agent limits" section**

Add a new `Section` (near the Sandboxing / Vibecop sections), matching the file's `Stepper` idiom (see the existing sandbox idle-timeout stepper):

```swift
                Section(header: Text("Agent Limits").font(.headline)) {
                    Stepper("Max goal iterations: \(config.maxGoalIterations)",
                            value: Binding(get: { config.maxGoalIterations },
                                           set: { config.maxGoalIterations = max(1, $0) }), in: 1...500)
                        .help("Hard cap on autonomous goal-loop turns before the agent summarizes and stops.")
                    Stepper("Loop-detection threshold: \(config.loopDetectionThreshold)",
                            value: Binding(get: { config.loopDetectionThreshold },
                                           set: { config.loopDetectionThreshold = max(2, $0) }), in: 2...20)
                        .help("Stop early if the agent repeats the exact same tool call this many times in a row.")
                    Stepper("Vibecop timeout: \(config.vibecopTimeoutSeconds)s",
                            value: Binding(get: { config.vibecopTimeoutSeconds },
                                           set: { config.vibecopTimeoutSeconds = max(1, $0) }), in: 1...30)
                        .help("How long to wait for the Vibecop guard before falling back to a manual approval prompt.")
                }
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 3: Manual verification**

Re-run Test D (subagent) and confirm: the approval banner now appears labeled "Subagent (…) wants to run …"; approving/denying works; multiple pending requests stack with "N more pending"; a subagent that would hang is cancelled after the timeout with a summary and its `iris-*` container is removed. Trigger a runaway `/goal` and confirm it stops at the cap (or on repetition) with a summary rather than looping.

- [ ] **Step 4: Commit**

```bash
git add Sources/iris/SettingsView.swift
git commit -m "feat(agent): Settings controls for goal cap, loop threshold, vibecop timeout"
```

---

## Self-Review

**Spec coverage:**
- A1 revert bypass → Task 7. ✓
- A2 approval queue (FIFO, @MainActor) → Task 4. ✓
- A3 origin labeling + surfacing → Tasks 4 (field), 7 (origin value), 6 (banner). ✓
- A4 Vibecop timeout (fail-open, cancel losing branch) → Tasks 2 (`withTimeout`), 5. ✓
- A5 sandbox-aware Vibecop → Task 5. ✓
- A6 `denyPendingApprovals(for:)` → Task 4. ✓
- B1 configurable cap → Tasks 3, 8. ✓
- B2 loop detection w/ deterministic signatures → Tasks 1, 8. ✓
- B3 summarize + hand back (soft LLM via goal_complete / hard deterministic) → Task 8 (soft), Task 9 (hard). ✓
- B4 subagent cancellation + teardown order → Task 9. ✓
- Config + Settings → Tasks 3, 10. ✓

**Placeholder scan:** No TBD/TODO; all code and tests concrete. Task 4 Step 3 notes a deliberate temporary shim resolved in Task 5 (documented, not a placeholder).

**Type consistency:** `LoopDetector.signature(toolName:args:)` / `record(_:)` / `reset()`; `withTimeout(seconds:_:)` / `TimeoutError`; `ToolApprovalRequest.{conversationId,origin}`; `pendingApprovals`; `enqueueUserApproval(...)`; `resolveApproval(_:)`; `denyPendingApprovals(for:)`; `requestApproval(...conversationId:origin:inSandbox:)`; `evaluateAction(...inSandbox:)`; `IrisEngine.roleLabel` / `approvalOrigin`; `maxGoalIterations` / `loopDetectionThreshold` / `vibecopTimeoutSeconds` are used identically across tasks.
