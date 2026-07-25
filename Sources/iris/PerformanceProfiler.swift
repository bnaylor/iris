import Foundation
import Combine

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
        func ms(_ c: PerfCategory) -> Double { categories[c]?.ms ?? 0 }
        let topLevel = ms(.primaryLLM) + ms(.toolExecution) + ms(.hooks) + ms(.contextAssembly)
        return max(0, totalMs - topLevel)
    }
}

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
