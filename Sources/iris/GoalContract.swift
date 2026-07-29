import Foundation

enum CriterionKind: String, Codable, Sendable, Equatable {
    case executable   // carries a runnable `check`
    case qualitative  // concrete "done looks like X"; no number
    case humanJudged  // "you decide" — never auto-graded
}

struct Criterion: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var text: String
    var kind: CriterionKind
    var check: String?   // command/test for .executable; nil otherwise
}

struct ContractChange: Codable, Equatable, Sendable {
    var date: Date = Date()
    var rationale: String
}

enum ContractState: String, Codable, Sendable, Equatable {
    case draft, locked
}

struct GoalContract: Codable, Equatable, Sendable {
    var id = UUID()
    var objective: String
    var criteria: [Criterion]
    var outOfScope: [String] = []
    var stopBefore: [String] = []
    var assumptions: [String] = []
    var changeLog: [ContractChange] = []
    var state: ContractState = .draft

    var isLocked: Bool { state == .locked }

    mutating func lock() { state = .locked }

    /// The ONLY sanctioned edit to criteria. On a locked contract a non-empty rationale is
    /// mandatory (edit rejected otherwise) and the change is recorded in the change-log.
    /// On a draft, edits are free and unlogged. Returns false iff the edit was rejected.
    @discardableResult
    mutating func applyCriteriaEdit(rationale: String, _ edit: (inout [Criterion]) -> Void) -> Bool {
        let blank = rationale.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if isLocked && blank { return false }
        edit(&criteria)
        if isLocked { changeLog.append(ContractChange(rationale: rationale)) }
        return true
    }

    /// The contract as injected into the goal loop's context (the "decision oracle").
    func oracleText() -> String {
        var s = "## Active Goal Contract (the oracle — consult before deciding)\n"
        s += "Objective: \(objective)\n\nDone when ALL of these hold:\n"
        for c in criteria {
            let tag: String
            switch c.kind {
            case .executable: tag = "[executable\(c.check.map { ": \($0)" } ?? "")]"
            case .qualitative: tag = "[qualitative]"
            case .humanJudged: tag = "[human-judged — you do not grade this]"
            }
            s += "  - \(tag) \(c.text)\n"
        }
        if !outOfScope.isEmpty { s += "\nOut of scope (do NOT do): \(outOfScope.joined(separator: "; "))\n" }
        if !stopBefore.isEmpty { s += "Stop and ask before: \(stopBefore.joined(separator: "; "))\n" }
        s += "\nChanging these criteria requires the `amend_goal_contract` tool with a rationale — never silently."
        return s
    }
}
