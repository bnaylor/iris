# Enhanced Performance Tracking

## Motivation

Iris already tracks **session-wide aggregate latency per operation** via `MetricsManager`
(min/avg/max/stddev for model calls by tier, vibecop, prompt-guard tiers 2/3, auxiliary,
rename), surfaced as a flat table in `DiagnosticsView`. That answers *"how slow is vibecop on
average this session"* but cannot answer the question that actually matters when Iris feels
slow: *"for the command I just ran, where did the 8 seconds go?"*

Iris runs several verification layers (vibecop, multi-tier prompt-injection protection) plus
tool calls and the primary LLM, much of it on CPU/Apple Silicon. This spec adds **per-command
attribution**: instrument the major subsystems, tag every timed span to the command that
triggered it, and add a new pane that breaks a command execution down by subsystem.

**Explicitly out of scope:** per-tool-name breakdown, LLM-by-tier split within a command,
tier-1/2/3 injection-guard split, and persistence of profiles across launches. (The existing
aggregate `MetricsManager` view already covers per-tier/per-op session stats.)

## Measurement Model

A turn is a sequence of **sequential top-level phases**: LLM call → tool phase → LLM call →
tool phase … until the turn finishes (see the `while !turnFinished` loop in
`IrisEngine.processInputBody`). Therefore the top-level buckets are roughly additive to the
turn's wall-clock time.

Vibecop and the injection guard run **nested inside** the tool phase (vibecop guards
`run_command`; the injection guard sanitizes tool output in `executeFunctionCall`). They are
therefore reported as **sub-measures of tool time, not added on top of it**. This matches the
user's mental model:

```
Command: "refactor the auth module"          total 8.2s
  Primary LLM ............................... 4.1s
  Tool execution ........................... 3.6s
    ├ Vibecop .............................. 1.0s
    ├ Injection guard ...................... 1.5s
    └ (tool self-work ≈ 1.1s)                       ← "waiting for tool calls"
  Hooks .................................... 0.3s
  Context assembly ......................... 0.1s
  Other/overhead ........................... 0.1s   (derived remainder)
```

`Other/overhead` is derived in the UI as `total − (primaryLLM + toolExecution + hooks +
contextAssembly)`, clamped at 0.

### Caveats (surfaced in-UI, not hidden)

1. **Parallel tools.** Tool calls in one phase run concurrently (`withTaskGroup` in the engine
   loop). The tool phase itself is measured as the phase wall-clock (correct), but the nested
   vibecop/injection sub-measures are summed across the concurrent calls, so in a rare
   multi-tool turn those sub-measures can exceed the tool-phase wall-clock. The UI notes this
   rather than fake-normalizing.
2. **Subagents** get their own `CommandProfile` (their own `processInput` turn). At the parent,
   a subagent's time rolls up under tool execution (the dispatch call), which is correct.

## Components

Each component is small and independently testable.

### `PerfCategory` (enum)

Six buckets: `primaryLLM`, `toolExecution`, `vibecop`, `injectionGuard`, `hooks`,
`contextAssembly`. Display names provided via a computed property. `Other` is not a stored
category — it is derived in the view.

### `CommandProfile` (struct)

One per command execution:
- `id: UUID`
- `label: String` — first ~40 chars of the triggering input
- `source: String` — "UI" / "System" / "Scheduler" / subagent role
- `startedAt: Date`
- `totalMs: Double` — turn wall-clock
- `categories: [PerfCategory: CategoryStat]` where `CategoryStat = (ms: Double, count: Int)`

Provides a `derivedOtherMs` computed helper for the view.

### `PerformanceProfiler` (`@MainActor`, `ObservableObject`, singleton)

Mirrors `MetricsManager`'s shape and threading (called via `await`, `@Published` state).

- `@TaskLocal static var currentTurnID: UUID?` — bound at the top of a turn; read by
  `record(...)` so every span (including those in inherited child tasks like parallel tool
  calls) attributes to the right command with no parameter threading.
- `@Published private(set) var recentCommands: [CommandProfile]` — ring buffer, last 20,
  in-memory only.
- `private var active: [UUID: CommandProfile]` — turns in flight.
- `func beginTurn(label:source:) -> UUID` — creates an active profile, returns its id.
- `func endTurn(_ id: UUID, totalMs:)` — finalizes into `recentCommands` (evicting oldest > 20).
- `func record(category:durationMs:)` — reads `currentTurnID`; adds to that active profile's
  bucket. No-op if there is no current turn (e.g. background work outside a command).

### Instrumentation helper

`measure<T>(_ category: PerfCategory, _ work: () async throws -> T) async rethrows -> T` —
times `work`, calls `PerformanceProfiler.shared.record(...)`. Used at the six points below.
Where a `MetricsManager.trackLatency` call already exists, the profiler `record` is added
alongside it (both systems fed from the same measured span); the aggregate view is unchanged.

### Instrumentation points

| Category         | Where                                                                 | New or existing span |
|------------------|-----------------------------------------------------------------------|----------------------|
| `primaryLLM`     | `LLMClient.generateContent` (already timed for MetricsManager)         | existing             |
| `toolExecution`  | the `withTaskGroup` tool phase in `processInputBody`                   | new                  |
| `vibecop`        | `VibecopService` (already timed)                                      | existing             |
| `injectionGuard` | `InjectionGuard.sanitize` (tier2/3, existing) + `PromptInjectionGuard.sanitizeUntrustedInput` (tier1, new) | mixed |
| `hooks`          | `HookManager.fire*` methods                                           | new                  |
| `contextAssembly`| `IrisEngine.ensureSystemPrompt`                                       | new                  |

### Turn boundary

In `IrisEngine.processInput`, wrap the body:

```swift
let turnID = await PerformanceProfiler.shared.beginTurn(label: input, source: source)
let start = ContinuousClock.now
await PerformanceProfiler.$currentTurnID.withValue(turnID) {
    await processInputBody(input, source: source, conversationId: conversationId)
}
let elapsed = start.duration(to: .now)
await PerformanceProfiler.shared.endTurn(turnID, totalMs: elapsed.milliseconds)
```

This sits just inside the existing `beginThinking()`/`endThinking()` bracket.

### UI

`DiagnosticsView` gains a segmented `Picker`:
- **By Command** (new, default): a `List` of `recentCommands` (label, total ms, relative time).
  Expanding a row (`DisclosureGroup`) shows category rows with a proportion bar and count;
  vibecop and injection guard are indented under tool execution; an `Other` row shows the
  derived remainder. A short footnote states the parallel-tools caveat.
- **Aggregate** (existing): today's `MetricsManager` table, unchanged.

## Testing

- `PerformanceProfiler` unit tests: `record` attributes to the current task-local turn;
  `record` outside a turn is a no-op; ring buffer evicts beyond 20; `endTurn` moves a profile
  from active to recent; category accumulation sums ms and increments count.
- `CommandProfile.derivedOtherMs` clamps at 0 and computes the remainder correctly.
- Task-local propagation test: a span recorded inside a child `Task` (simulating a parallel
  tool call) attributes to the parent turn.

## Rollout

Additive only. No changes to `MetricsManager`, existing metrics call sites keep working, and
old persisted conversations are unaffected (profiles are in-memory).
