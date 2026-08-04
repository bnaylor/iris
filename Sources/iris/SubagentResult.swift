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
