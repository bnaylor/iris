import Foundation

/// The grader's verdict for one criterion. `met`/`notMet`/`cannotVerify` are gradable outcomes;
/// `humanPending` marks a `humanJudged` criterion the grader must not auto-grade (spec §4.4).
enum CriterionVerdictValue: String, Codable, Sendable, Equatable {
    case met
    case notMet = "not_met"
    case cannotVerify = "cannot_verify"
    case humanPending = "human_pending"
}

/// How a verdict was reached: a run check (executable), an LLM judgement (qualitative), or
/// deferred to a human (humanJudged).
enum VerdictMethod: String, Codable, Sendable, Equatable {
    case check
    case judge
    case human
}

struct CriterionVerdict: Codable, Identifiable, Equatable, Sendable {
    var id: UUID { criterionId }
    var criterionId: UUID
    var criterionText: String
    var kind: CriterionKind
    var verdict: CriterionVerdictValue
    var evidence: String
    var method: VerdictMethod
}

enum EvaluationStatus: String, Codable, Sendable, Equatable {
    case verifying   // grader running; verdicts not yet in
    case graded      // grader finished normally
    case failed      // grader errored or hit its iteration cap
}

struct GoalEvaluation: Codable, Equatable, Sendable {
    var id = UUID()
    var status: EvaluationStatus
    var criteria: [CriterionVerdict]
    var startedAt: Date
    var completedAt: Date?
}
