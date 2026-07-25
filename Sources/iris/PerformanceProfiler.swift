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
        func ms(_ c: PerfCategory) -> Double { categories[c]?.ms ?? 0 }
        let topLevel = ms(.primaryLLM) + ms(.toolExecution) + ms(.hooks) + ms(.contextAssembly)
        return max(0, totalMs - topLevel)
    }
}
