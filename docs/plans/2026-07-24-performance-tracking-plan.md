# Enhanced Performance Tracking Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add per-command performance attribution — break each command execution down by subsystem (primary LLM, tool execution, vibecop, injection guard, hooks, context assembly) and show it in a new "By Command" pane of the diagnostics window.

**Architecture:** A `PerformanceProfiler` singleton accumulates timed spans into a `CommandProfile` per turn. Spans are attributed to the right command via a `@TaskLocal` turn id bound at the top of `IrisEngine.processInput`, so nested and parallel (`withTaskGroup`) spans land in the right bucket with no parameter threading. Six subsystems self-instrument via `measure`/`measureSync` helpers. The existing session-wide `MetricsManager` is untouched.

**Tech Stack:** Swift, SwiftUI, Swift Testing (`import Testing`, `@Test`), macOS actors/async-await.

## Global Constraints

- Timing uses `CFAbsoluteTimeGetCurrent()` and `* 1000.0` for milliseconds, matching existing call sites (`LLMClient.swift:95`, `VibecopService.swift:56`).
- Profiles are **in-memory only** — no persistence across launches. Ring buffer holds the last **20** command executions.
- `PerfCategory` has exactly six cases: `primaryLLM`, `toolExecution`, `vibecop`, `injectionGuard`, `hooks`, `contextAssembly`. "Other" is derived in the view, never stored.
- Additive to the codebase: do not change `MetricsManager` or existing `trackLatency` call sites' behavior; add profiler calls alongside them.
- New tests use Swift Testing (`import Testing`, `@Test`, `#expect`), matching `Tests/irisTests/ADCCredentialManagerTests.swift`.

---

### Task 1: Value types (`PerfCategory`, `CategoryStat`, `CommandProfile`)

**Files:**
- Create: `Sources/iris/PerformanceProfiler.swift`
- Test: `Tests/irisTests/PerformanceProfilerTests.swift`

**Interfaces:**
- Produces:
  - `enum PerfCategory: String, CaseIterable, Sendable` with cases `primaryLLM, toolExecution, vibecop, injectionGuard, hooks, contextAssembly`; `var displayName: String`; `var isGuardSubMeasure: Bool`.
  - `struct CategoryStat: Sendable { var ms: Double; var count: Int; mutating func add(_ durationMs: Double) }`
  - `struct CommandProfile: Identifiable, Sendable { let id: UUID; let label: String; let source: String; let startedAt: Date; var totalMs: Double; var categories: [PerfCategory: CategoryStat]; mutating func add(_ category: PerfCategory, durationMs: Double); var derivedOtherMs: Double }`

- [ ] **Step 1: Write the failing test**

Create `Tests/irisTests/PerformanceProfilerTests.swift`:

```swift
import Testing
import Foundation
@testable import iris

@Suite("PerformanceProfiler value types")
struct PerformanceProfilerValueTypeTests {

    @Test("CommandProfile.add accumulates ms and count per category")
    func addAccumulates() {
        var profile = CommandProfile(id: UUID(), label: "test", source: "UI", startedAt: Date())
        profile.add(.primaryLLM, durationMs: 100)
        profile.add(.primaryLLM, durationMs: 50)
        profile.add(.vibecop, durationMs: 30)

        #expect(profile.categories[.primaryLLM]?.ms == 150)
        #expect(profile.categories[.primaryLLM]?.count == 2)
        #expect(profile.categories[.vibecop]?.ms == 30)
        #expect(profile.categories[.vibecop]?.count == 1)
    }

    @Test("derivedOtherMs is total minus top-level phases, clamped at 0")
    func derivedOther() {
        var profile = CommandProfile(id: UUID(), label: "test", source: "UI", startedAt: Date())
        profile.totalMs = 1000
        profile.add(.primaryLLM, durationMs: 400)
        profile.add(.toolExecution, durationMs: 300)
        profile.add(.hooks, durationMs: 50)
        profile.add(.contextAssembly, durationMs: 50)
        // vibecop/injection are sub-measures of tool time and must NOT reduce Other
        profile.add(.vibecop, durationMs: 200)
        profile.add(.injectionGuard, durationMs: 100)

        #expect(profile.derivedOtherMs == 200) // 1000 - (400+300+50+50)
    }

    @Test("derivedOtherMs clamps to 0 when phases exceed total")
    func derivedOtherClamps() {
        var profile = CommandProfile(id: UUID(), label: "test", source: "UI", startedAt: Date())
        profile.totalMs = 100
        profile.add(.primaryLLM, durationMs: 400)
        #expect(profile.derivedOtherMs == 0)
    }

    @Test("guard categories are flagged as sub-measures")
    func guardFlag() {
        #expect(PerfCategory.vibecop.isGuardSubMeasure)
        #expect(PerfCategory.injectionGuard.isGuardSubMeasure)
        #expect(!PerfCategory.toolExecution.isGuardSubMeasure)
        #expect(!PerfCategory.primaryLLM.isGuardSubMeasure)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter PerformanceProfilerValueTypeTests`
Expected: FAIL — `cannot find 'CommandProfile' in scope`.

- [ ] **Step 3: Write minimal implementation**

Create `Sources/iris/PerformanceProfiler.swift`:

```swift
import Foundation

/// A subsystem bucket a slice of command-execution time is attributed to.
/// "Other" is not a case here — it is derived in the view as the remainder.
public enum PerfCategory: String, CaseIterable, Sendable {
    case primaryLLM
    case toolExecution
    case vibecop
    case injectionGuard
    case hooks
    case contextAssembly

    public var displayName: String {
        switch self {
        case .primaryLLM: return "Primary LLM"
        case .toolExecution: return "Tool execution"
        case .vibecop: return "Vibecop"
        case .injectionGuard: return "Injection guard"
        case .hooks: return "Hooks"
        case .contextAssembly: return "Context assembly"
        }
    }

    /// Vibecop and the injection guard run *inside* the tool phase, so the UI shows them
    /// indented under tool execution rather than as additive top-level rows.
    public var isGuardSubMeasure: Bool {
        self == .vibecop || self == .injectionGuard
    }
}

public struct CategoryStat: Sendable {
    public var ms: Double = 0
    public var count: Int = 0

    public mutating func add(_ durationMs: Double) {
        ms += durationMs
        count += 1
    }
}

public struct CommandProfile: Identifiable, Sendable {
    public let id: UUID
    public let label: String
    public let source: String
    public let startedAt: Date
    public var totalMs: Double = 0
    public var categories: [PerfCategory: CategoryStat] = [:]

    public init(id: UUID, label: String, source: String, startedAt: Date) {
        self.id = id
        self.label = label
        self.source = source
        self.startedAt = startedAt
    }

    public mutating func add(_ category: PerfCategory, durationMs: Double) {
        categories[category, default: CategoryStat()].add(durationMs)
    }

    /// Unattributed remainder: turn wall-clock minus the sequential top-level phases.
    /// Guard sub-measures (vibecop/injection) are excluded because they are already counted
    /// inside tool execution.
    public var derivedOtherMs: Double {
        let topLevel = (categories[.primaryLLM]?.ms ?? 0)
            + (categories[.toolExecution]?.ms ?? 0)
            + (categories[.hooks]?.ms ?? 0)
            + (categories[.contextAssembly]?.ms ?? 0)
        return max(0, totalMs - topLevel)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter PerformanceProfilerValueTypeTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/iris/PerformanceProfiler.swift Tests/irisTests/PerformanceProfilerTests.swift
git commit -m "feat(perf): PerfCategory, CategoryStat, CommandProfile value types"
```

---

### Task 2: `PerformanceProfiler` singleton (turn lifecycle + ring buffer)

**Files:**
- Modify: `Sources/iris/PerformanceProfiler.swift`
- Test: `Tests/irisTests/PerformanceProfilerTests.swift`

**Interfaces:**
- Consumes: `CommandProfile`, `PerfCategory` (Task 1).
- Produces:
  - `final class PerformanceProfiler: ObservableObject, @unchecked Sendable`
  - `static let shared: PerformanceProfiler`
  - `@TaskLocal static var currentTurnID: UUID?`
  - `@Published private(set) var recentCommands: [CommandProfile]`
  - `func beginTurn(label: String, source: String) -> UUID`
  - `func record(turnID: UUID?, category: PerfCategory, durationMs: Double)`
  - `func endTurn(_ id: UUID, totalMs: Double)`
  - `static let maxRecent = 20`

**Notes for implementer:** `record`/`beginTurn` are synchronous and thread-safe (NSLock-protected) so they can be called from any actor, any thread, including synchronous code (the tier-1 guard). `endTurn` moves the finished profile into `recentCommands`; because `recentCommands` is `@Published` (SwiftUI observes it) its mutation is dispatched to the main thread.

- [ ] **Step 1: Write the failing test**

Append to `Tests/irisTests/PerformanceProfilerTests.swift`:

```swift
@Suite("PerformanceProfiler lifecycle")
struct PerformanceProfilerLifecycleTests {

    @Test("record attributes to the active turn")
    func recordAttributes() {
        let profiler = PerformanceProfiler()
        let id = profiler.beginTurn(label: "hello world", source: "UI")
        profiler.record(turnID: id, category: .primaryLLM, durationMs: 42)
        profiler.record(turnID: id, category: .primaryLLM, durationMs: 8)

        #expect(profiler.activeProfileForTesting(id)?.categories[.primaryLLM]?.ms == 50)
    }

    @Test("record with nil turn id is a no-op")
    func recordNilNoop() {
        let profiler = PerformanceProfiler()
        profiler.record(turnID: nil, category: .primaryLLM, durationMs: 42) // must not crash
        #expect(profiler.activeCountForTesting == 0)
    }

    @Test("endTurn moves the profile into recentCommands with its total")
    func endTurnFinalizes() async {
        let profiler = PerformanceProfiler()
        let id = profiler.beginTurn(label: "hello", source: "UI")
        profiler.record(turnID: id, category: .toolExecution, durationMs: 10)
        profiler.endTurn(id, totalMs: 100)

        // recentCommands is updated on the main thread; give it a tick.
        try? await Task.sleep(nanoseconds: 50_000_000)
        await MainActor.run {
            #expect(profiler.recentCommands.count == 1)
            #expect(profiler.recentCommands.first?.totalMs == 100)
            #expect(profiler.recentCommands.first?.label == "hello")
        }
        #expect(profiler.activeCountForTesting == 0)
    }

    @Test("ring buffer keeps only the most recent maxRecent profiles")
    func ringBufferEvicts() async {
        let profiler = PerformanceProfiler()
        for i in 0..<(PerformanceProfiler.maxRecent + 5) {
            let id = profiler.beginTurn(label: "cmd \(i)", source: "UI")
            profiler.endTurn(id, totalMs: Double(i))
        }
        try? await Task.sleep(nanoseconds: 50_000_000)
        await MainActor.run {
            #expect(profiler.recentCommands.count == PerformanceProfiler.maxRecent)
            // newest last; oldest ("cmd 0".."cmd 4") evicted
            #expect(profiler.recentCommands.last?.label == "cmd \(PerformanceProfiler.maxRecent + 4)")
        }
    }

    @Test("a span recorded in a child task attributes to the parent turn")
    func taskLocalPropagation() async {
        let profiler = PerformanceProfiler()
        let id = profiler.beginTurn(label: "parent", source: "UI")
        await PerformanceProfiler.$currentTurnID.withValue(id) {
            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    // Inherits currentTurnID from parent.
                    profiler.record(turnID: PerformanceProfiler.currentTurnID, category: .vibecop, durationMs: 7)
                }
                await group.waitForAll()
            }
        }
        #expect(profiler.activeProfileForTesting(id)?.categories[.vibecop]?.ms == 7)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter PerformanceProfilerLifecycleTests`
Expected: FAIL — `value of type 'PerformanceProfiler' has no member 'beginTurn'`.

- [ ] **Step 3: Write minimal implementation**

Append to `Sources/iris/PerformanceProfiler.swift`:

```swift
import Combine

public final class PerformanceProfiler: ObservableObject, @unchecked Sendable {
    public static let shared = PerformanceProfiler()
    public static let maxRecent = 20

    /// Bound at the top of a turn (`IrisEngine.processInput`). Inherited by child tasks
    /// (e.g. parallel tool calls), so spans attribute to the right command automatically.
    @TaskLocal public static var currentTurnID: UUID?

    /// Observed by the diagnostics UI. Only mutated on the main thread.
    @Published public private(set) var recentCommands: [CommandProfile] = []

    private let lock = NSLock()
    private var active: [UUID: CommandProfile] = [:]

    public init() {}

    public func beginTurn(label: String, source: String) -> UUID {
        let id = UUID()
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let short = trimmed.count > 40 ? String(trimmed.prefix(40)) + "…" : trimmed
        let profile = CommandProfile(id: id, label: short.isEmpty ? "(empty)" : short,
                                     source: source, startedAt: Date())
        lock.lock()
        active[id] = profile
        lock.unlock()
        return id
    }

    public func record(turnID: UUID?, category: PerfCategory, durationMs: Double) {
        guard let turnID else { return }
        lock.lock()
        active[turnID]?.add(category, durationMs: durationMs)
        lock.unlock()
    }

    public func endTurn(_ id: UUID, totalMs: Double) {
        lock.lock()
        var profile = active.removeValue(forKey: id)
        lock.unlock()
        guard profile != nil else { return }
        profile!.totalMs = totalMs
        let finished = profile!
        // @Published mutation must happen on the main thread.
        if Thread.isMainThread {
            appendRecent(finished)
        } else {
            DispatchQueue.main.async { [weak self] in self?.appendRecent(finished) }
        }
    }

    private func appendRecent(_ profile: CommandProfile) {
        recentCommands.append(profile)
        if recentCommands.count > Self.maxRecent {
            recentCommands.removeFirst(recentCommands.count - Self.maxRecent)
        }
    }

    // MARK: - Test hooks
    #if DEBUG
    func activeProfileForTesting(_ id: UUID) -> CommandProfile? {
        lock.lock(); defer { lock.unlock() }
        return active[id]
    }
    var activeCountForTesting: Int {
        lock.lock(); defer { lock.unlock() }
        return active.count
    }
    #endif
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter PerformanceProfilerLifecycleTests`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/iris/PerformanceProfiler.swift Tests/irisTests/PerformanceProfilerTests.swift
git commit -m "feat(perf): PerformanceProfiler turn lifecycle + ring buffer"
```

---

### Task 3: `measure` / `measureSync` instrumentation helpers

**Files:**
- Modify: `Sources/iris/PerformanceProfiler.swift`
- Test: `Tests/irisTests/PerformanceProfilerTests.swift`

**Interfaces:**
- Produces (free functions, file scope):
  - `func measure<T>(_ category: PerfCategory, _ work: () async throws -> T) async rethrows -> T`
  - `func measureSync<T>(_ category: PerfCategory, _ work: () throws -> T) rethrows -> T`
- Both read `PerformanceProfiler.currentTurnID` in the caller's task context and call `PerformanceProfiler.shared.record(...)`.

**Note:** These call `.shared`. The lifecycle tests use a local instance; these helper tests verify attribution against `.shared` by binding the task-local.

- [ ] **Step 1: Write the failing test**

Append to `Tests/irisTests/PerformanceProfilerTests.swift`:

```swift
@Suite("PerformanceProfiler measure helpers")
struct PerformanceProfilerMeasureTests {

    @Test("measure records elapsed time to the current turn on shared profiler")
    func measureRecords() async {
        let id = PerformanceProfiler.shared.beginTurn(label: "measure", source: "UI")
        await PerformanceProfiler.$currentTurnID.withValue(id) {
            _ = await measure(.primaryLLM) {
                try? await Task.sleep(nanoseconds: 20_000_000) // ~20ms
            }
        }
        let ms = PerformanceProfiler.shared.activeProfileForTesting(id)?.categories[.primaryLLM]?.ms ?? 0
        #expect(ms >= 10) // generous lower bound to avoid flakiness
        PerformanceProfiler.shared.endTurn(id, totalMs: ms)
    }

    @Test("measureSync records and returns the value")
    func measureSyncReturns() {
        let id = PerformanceProfiler.shared.beginTurn(label: "sync", source: "UI")
        let out: Int = PerformanceProfiler.$currentTurnID.withValue(id) {
            measureSync(.injectionGuard) { 21 + 21 }
        }
        #expect(out == 42)
        #expect((PerformanceProfiler.shared.activeProfileForTesting(id)?.categories[.injectionGuard]?.count ?? 0) == 1)
        PerformanceProfiler.shared.endTurn(id, totalMs: 0)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter PerformanceProfilerMeasureTests`
Expected: FAIL — `cannot find 'measure' in scope`.

- [ ] **Step 3: Write minimal implementation**

Append to `Sources/iris/PerformanceProfiler.swift`:

```swift
/// Time an async subsystem span and attribute it to the current turn.
@discardableResult
public func measure<T>(_ category: PerfCategory, _ work: () async throws -> T) async rethrows -> T {
    let turnID = PerformanceProfiler.currentTurnID
    let start = CFAbsoluteTimeGetCurrent()
    do {
        let result = try await work()
        PerformanceProfiler.shared.record(turnID: turnID, category: category,
                                          durationMs: (CFAbsoluteTimeGetCurrent() - start) * 1000.0)
        return result
    } catch {
        PerformanceProfiler.shared.record(turnID: turnID, category: category,
                                          durationMs: (CFAbsoluteTimeGetCurrent() - start) * 1000.0)
        throw error
    }
}

/// Time a synchronous subsystem span and attribute it to the current turn.
@discardableResult
public func measureSync<T>(_ category: PerfCategory, _ work: () throws -> T) rethrows -> T {
    let turnID = PerformanceProfiler.currentTurnID
    let start = CFAbsoluteTimeGetCurrent()
    defer {
        PerformanceProfiler.shared.record(turnID: turnID, category: category,
                                          durationMs: (CFAbsoluteTimeGetCurrent() - start) * 1000.0)
    }
    return try work()
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter PerformanceProfilerMeasureTests`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/iris/PerformanceProfiler.swift Tests/irisTests/PerformanceProfilerTests.swift
git commit -m "feat(perf): measure/measureSync instrumentation helpers"
```

---

### Task 4: Bind the turn id in `IrisEngine.processInput`

**Files:**
- Modify: `Sources/iris/iris.swift:79-86`

**Interfaces:**
- Consumes: `PerformanceProfiler.beginTurn`, `.endTurn`, `.$currentTurnID` (Tasks 2).

**Note:** This is engine wiring that is exercised by the full app, not a unit test. Verify by build. The current `processInput` (lines 79-86) brackets the body with `beginThinking()`/`endThinking()`; wrap the profiler turn just inside that.

- [ ] **Step 1: Apply the edit**

Replace the body of `processInput` (currently):

```swift
        let stateForThinking = state
        await MainActor.run { stateForThinking?.beginThinking() }
        await processInputBody(input, source: source, conversationId: conversationId)
        await MainActor.run { stateForThinking?.endThinking() }
```

with:

```swift
        let stateForThinking = state
        await MainActor.run { stateForThinking?.beginThinking() }
        let turnID = PerformanceProfiler.shared.beginTurn(label: input, source: source)
        let turnStart = CFAbsoluteTimeGetCurrent()
        await PerformanceProfiler.$currentTurnID.withValue(turnID) {
            await processInputBody(input, source: source, conversationId: conversationId)
        }
        PerformanceProfiler.shared.endTurn(turnID, totalMs: (CFAbsoluteTimeGetCurrent() - turnStart) * 1000.0)
        await MainActor.run { stateForThinking?.endThinking() }
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/iris/iris.swift
git commit -m "feat(perf): bind per-turn profiler id around processInputBody"
```

---

### Task 5: Instrument the six subsystems

**Files:**
- Modify: `Sources/iris/LLMClient.swift:95-101` (primaryLLM)
- Modify: `Sources/iris/iris.swift:388-414` (toolExecution — the `withTaskGroup` block)
- Modify: `Sources/iris/VibecopService.swift:60,72,78,81` (vibecop)
- Modify: `Sources/iris/InjectionGuard.swift:26` (injectionGuard, tier2/3 entry `sanitize`)
- Modify: `Sources/iris/PromptInjectionGuard.swift:15` (injectionGuard, tier1 `sanitizeUntrustedInput`)
- Modify: `Sources/iris/HookManager.swift:101-…` (hooks — `fireEvent`)
- Modify: `Sources/iris/iris.swift:24-32` (contextAssembly — `ensureSystemPrompt`)

**Interfaces:**
- Consumes: `measure`, `measureSync`, `PerformanceProfiler.shared.record`, `PerfCategory` (Tasks 1-3).

**Note:** Existing `trackLatency` calls stay. Each edit adds a profiler `record` alongside the existing timing, or wraps a body with `measure`. Not unit-tested (needs the running app); verify by build. Where a `durationMs` is already computed, reuse it and add one `record` line reading `PerformanceProfiler.currentTurnID`.

- [ ] **Step 1: primaryLLM — `LLMClient.swift`**

After the existing success line (`await MetricsManager.shared.trackLatency(operation: metricOp, modelName: modelName, durationMs: durationMs, success: true)`), add:

```swift
            PerformanceProfiler.shared.record(turnID: PerformanceProfiler.currentTurnID, category: .primaryLLM, durationMs: durationMs)
```

Add the same line after the failure `trackLatency` in the `catch` block (using its local `durationMs`).

- [ ] **Step 2: toolExecution — `iris.swift`**

Wrap the parallel tool phase. Change:

```swift
                    let results = await withTaskGroup(of: (Int, String).self) { group in
```

to:

```swift
                    let results = await measure(.toolExecution) {
                        await withTaskGroup(of: (Int, String).self) { group in
```

and add a matching closing `}` after the existing `withTaskGroup` closure returns (i.e. wrap the whole `let results = ...` assignment). Ensure the closure returns `collection` outward. Concretely the block becomes:

```swift
                    let results = await measure(.toolExecution) {
                        await withTaskGroup(of: (Int, String).self) { group in
                            for (index, call) in toolCalls.enumerated() {
                                group.addTask {
                                    // ...unchanged body...
                                    let result = await self.executeFunctionCall(call, conversationId: conversationId, workspacePath: workspacePath)
                                    return (index, result)
                                }
                            }
                            var collection: [Int: String] = [:]
                            for await (index, result) in group {
                                collection[index] = result
                            }
                            return collection
                        }
                    }
```

- [ ] **Step 3: vibecop — `VibecopService.swift`**

The method already computes `durationMs`. After the success `trackLatency` (line 72) add:

```swift
                PerformanceProfiler.shared.record(turnID: PerformanceProfiler.currentTurnID, category: .vibecop, durationMs: durationMs)
```

Do the same after each failure `trackLatency` (lines 78 and 82), each using the `durationMs` in scope.

- [ ] **Step 4: injectionGuard tier2/3 — `InjectionGuard.swift`**

Wrap the body of `static func sanitize(_:contextTag:maxTier:)`. Immediately inside the function, capture the turn id and time the whole thing. Change the signature body to compute and record on exit:

```swift
    public static func sanitize(_ rawInput: String, contextTag: String = "", maxTier: SanitizationTier = .tier1_structural) async -> String {
        let __turnID = PerformanceProfiler.currentTurnID
        let __start = CFAbsoluteTimeGetCurrent()
        defer {
            PerformanceProfiler.shared.record(turnID: __turnID, category: .injectionGuard,
                                              durationMs: (CFAbsoluteTimeGetCurrent() - __start) * 1000.0)
        }
        // ...existing body unchanged...
```

(`defer` runs on every return path, including early returns inside the existing body.)

- [ ] **Step 5: injectionGuard tier1 — `PromptInjectionGuard.swift`**

Wrap the body of `static func sanitizeUntrustedInput(_:)` with `measureSync`:

```swift
    static func sanitizeUntrustedInput(_ rawInput: String) -> String {
        measureSync(.injectionGuard) {
            // ...existing body unchanged (as the closure's return)...
        }
    }
```

If the existing body has multiple `return` statements, either convert them to closure returns or capture the result in a `let` inside the closure and return it; keep behavior identical.

- [ ] **Step 6: hooks — `HookManager.swift`**

In `fireEvent`, after the early-return guard (which returns when no hooks are registered), time the hook-execution loop. Wrap from just before `var currentData = payload` through the end of the loop. Simplest: capture turn id + start right after the guard, and record via `defer`:

```swift
    private func fireEvent(eventName: String, targetMatcher: String, payload: Data?) async -> HookDecision {
        guard let config = config, let eventHooks = config.hooks[eventName] else {
            return .proceed(modifiedData: nil) // No hooks registered — not counted
        }
        let __turnID = PerformanceProfiler.currentTurnID
        let __start = CFAbsoluteTimeGetCurrent()
        defer {
            PerformanceProfiler.shared.record(turnID: __turnID, category: .hooks,
                                              durationMs: (CFAbsoluteTimeGetCurrent() - __start) * 1000.0)
        }
        // ...existing body unchanged...
```

- [ ] **Step 7: contextAssembly — `iris.swift` `ensureSystemPrompt`**

The system prompt is cached after first build. Time only the miss path. Change:

```swift
    private func ensureSystemPrompt() async -> Content {
        if let existing = systemPrompt { return existing }
        let soul = await manager.loadSOUL()
        let skills = await manager.discoverSkills()
        let steering = SystemSteering.shipped()
        let prompt = Content(role: "system", parts: [Part(text: "\(soul)\n\n\(skills)\n\n\(steering)", functionCall: nil, functionResponse: nil)])
        systemPrompt = prompt
        return prompt
    }
```

to:

```swift
    private func ensureSystemPrompt() async -> Content {
        if let existing = systemPrompt { return existing }
        return await measure(.contextAssembly) {
            let soul = await manager.loadSOUL()
            let skills = await manager.discoverSkills()
            let steering = SystemSteering.shipped()
            let prompt = Content(role: "system", parts: [Part(text: "\(soul)\n\n\(skills)\n\n\(steering)", functionCall: nil, functionResponse: nil)])
            systemPrompt = prompt
            return prompt
        }
    }
```

- [ ] **Step 8: Build**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 9: Commit**

```bash
git add Sources/iris/LLMClient.swift Sources/iris/iris.swift Sources/iris/VibecopService.swift Sources/iris/InjectionGuard.swift Sources/iris/PromptInjectionGuard.swift Sources/iris/HookManager.swift
git commit -m "feat(perf): instrument LLM, tools, vibecop, injection guard, hooks, context assembly"
```

---

### Task 6: "By Command" diagnostics pane

**Files:**
- Modify: `Sources/iris/DiagnosticsView.swift`

**Interfaces:**
- Consumes: `PerformanceProfiler.shared.recentCommands`, `CommandProfile`, `PerfCategory` (Tasks 1-2).

**Note:** SwiftUI view; verify by build + manual smoke. The existing table becomes the "Aggregate" tab; a new "By Command" tab is added and shown by default.

- [ ] **Step 1: Rewrite `DiagnosticsView.swift`**

```swift
import SwiftUI

struct DiagnosticsView: View {
    @ObservedObject private var metrics = MetricsManager.shared
    @ObservedObject private var profiler = PerformanceProfiler.shared
    @State private var mode: Mode = .byCommand

    enum Mode: String, CaseIterable, Identifiable {
        case byCommand = "By Command"
        case aggregate = "Aggregate"
        var id: String { rawValue }
    }

    var body: some View {
        VStack {
            Picker("", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding([.horizontal, .top])

            switch mode {
            case .byCommand: byCommand
            case .aggregate: aggregate
            }
        }
        .frame(minWidth: 600, minHeight: 400)
    }

    // MARK: - By Command

    private var byCommand: some View {
        Group {
            if profiler.recentCommands.isEmpty {
                Spacer()
                Text("No commands recorded yet. Run a command to see where its time goes.")
                    .foregroundColor(.secondary)
                Spacer()
            } else {
                List {
                    // Newest first.
                    ForEach(profiler.recentCommands.reversed()) { profile in
                        DisclosureGroup {
                            CommandBreakdownView(profile: profile)
                        } label: {
                            HStack {
                                Text(profile.label).lineLimit(1)
                                Spacer()
                                Text(String(format: "%.0f ms", profile.totalMs))
                                    .foregroundColor(profile.totalMs > 5000 ? .orange : .secondary)
                                    .monospacedDigit()
                            }
                        }
                    }
                }
                Text("Vibecop and Injection guard run inside Tool execution (shown indented). With parallel tool calls their sub-totals can exceed the tool-phase time.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding([.horizontal, .bottom])
            }
        }
    }

    // MARK: - Aggregate (unchanged from prior behavior)

    private var aggregate: some View {
        Table(metrics.aggregatedMetrics) {
            TableColumn("Operation") { Text($0.operation.rawValue) }
            TableColumn("Model") { Text($0.modelName) }
            TableColumn("Count") { Text("\($0.count)") }
            TableColumn("Min") { Text(String(format: "%.0f ms", $0.minMs)) }
            TableColumn("Avg") { Text(String(format: "%.0f ms", $0.avgMs)) }
            TableColumn("Max") { metric in
                Text(String(format: "%.0f ms", metric.maxMs))
                    .foregroundColor(metric.maxMs > 5000 ? .orange : .primary)
            }
            TableColumn("StdDev") { Text(String(format: "%.0f ms", $0.stddevMs)) }
        }
    }
}

/// Category rows for one command, with guard layers indented under tool execution.
private struct CommandBreakdownView: View {
    let profile: CommandProfile

    // Top-level order; guards are rendered indented under toolExecution.
    private let topLevel: [PerfCategory] = [.primaryLLM, .toolExecution, .hooks, .contextAssembly]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(topLevel, id: \.self) { cat in
                if let stat = profile.categories[cat] {
                    row(name: cat.displayName, ms: stat.ms, count: stat.count, indent: 0)
                    if cat == .toolExecution {
                        ForEach([PerfCategory.vibecop, .injectionGuard], id: \.self) { g in
                            if let gstat = profile.categories[g] {
                                row(name: g.displayName, ms: gstat.ms, count: gstat.count, indent: 1)
                            }
                        }
                    }
                }
            }
            row(name: "Other/overhead", ms: profile.derivedOtherMs, count: 0, indent: 0)
        }
        .padding(.vertical, 4)
    }

    private func row(name: String, ms: Double, count: Int, indent: Int) -> some View {
        let fraction = profile.totalMs > 0 ? min(1.0, ms / profile.totalMs) : 0
        return HStack(spacing: 8) {
            Text(name)
                .padding(.leading, CGFloat(indent) * 16)
                .frame(width: 180, alignment: .leading)
                .foregroundColor(indent > 0 ? .secondary : .primary)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color.secondary.opacity(0.15))
                    Rectangle().fill(indent > 0 ? Color.orange.opacity(0.5) : Color.accentColor.opacity(0.6))
                        .frame(width: geo.size.width * CGFloat(fraction))
                }
                .cornerRadius(3)
            }
            .frame(height: 12)
            Text(String(format: "%.0f ms", ms))
                .frame(width: 70, alignment: .trailing)
                .monospacedDigit()
                .foregroundColor(.secondary)
        }
        .font(.caption)
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 3: Manual smoke test**

Run the app, run a command that calls a tool, open the diagnostics window (chart icon, top-right). Verify the "By Command" tab lists the command, expanding it shows Primary LLM / Tool execution (with Vibecop + Injection guard indented) / Hooks / Context assembly / Other with proportion bars. Toggle to "Aggregate" and confirm the old table still renders.

- [ ] **Step 4: Commit**

```bash
git add Sources/iris/DiagnosticsView.swift
git commit -m "feat(perf): By Command diagnostics pane with per-subsystem breakdown"
```

---

## Self-Review

**Spec coverage:**
- Per-command attribution → Tasks 1-4. ✓
- Six subsystem categories instrumented → Task 5 (all six). ✓
- Nested measurement model (guards as sub-measures of tools; Other derived) → `CommandProfile.derivedOtherMs` (Task 1), UI indentation (Task 6). ✓
- New "By Command" pane + existing Aggregate retained → Task 6. ✓
- In-memory ring buffer, last 20 → Task 2 (`maxRecent = 20`). ✓
- Task-local propagation for parallel/nested spans → Task 2 test + Task 4 binding. ✓
- Caveats surfaced in-UI (parallel tools) → Task 6 footnote. ✓
- `MetricsManager` untouched → Task 5 adds alongside, aggregate tab unchanged. ✓

**Placeholder scan:** No TBD/TODO; all code shown; test bodies concrete. ✓

**Type consistency:** `beginTurn(label:source:) -> UUID`, `record(turnID:category:durationMs:)`, `endTurn(_:totalMs:)`, `add(_:durationMs:)`, `derivedOtherMs`, `currentTurnID`, `recentCommands`, `maxRecent` used identically across tasks. ✓
