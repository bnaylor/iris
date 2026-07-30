import Testing
import Foundation
@testable import iris

@Suite("GoalEvaluation model")
struct GoalEvaluationTests {
    private func sample() -> GoalEvaluation {
        GoalEvaluation(
            status: .graded,
            criteria: [
                CriterionVerdict(criterionId: UUID(), criterionText: "swift build green",
                                 kind: .executable, verdict: .met,
                                 evidence: "swift build → exit 0", method: .check),
                CriterionVerdict(criterionId: UUID(), criterionText: "looks good",
                                 kind: .humanJudged, verdict: .humanPending,
                                 evidence: "", method: .human)
            ],
            startedAt: Date(timeIntervalSince1970: 100),
            completedAt: Date(timeIntervalSince1970: 200))
    }

    @Test("round-trips through Codable")
    func codable() throws {
        let e = sample()
        let back = try JSONDecoder().decode(GoalEvaluation.self, from: JSONEncoder().encode(e))
        #expect(back == e)
    }

    @Test("a legacy conversation with no evaluation decodes with nil")
    func legacyNil() throws {
        let json = #"{"id":"\#(UUID().uuidString)","title":"t","messages":[],"history":[],"tokenUsage":{"promptTokenCount":0,"candidatesTokenCount":0,"totalTokenCount":0},"messageCountSinceReflection":0}"#
        let conv = try JSONDecoder().decode(Conversation.self, from: Data(json.utf8))
        #expect(conv.lastGoalEvaluation == nil)
    }

    @Test("verdict + method + status enums are string-coded")
    func rawValues() {
        #expect(CriterionVerdictValue.notMet.rawValue == "not_met")
        #expect(CriterionVerdictValue.cannotVerify.rawValue == "cannot_verify")
        #expect(CriterionVerdictValue.humanPending.rawValue == "human_pending")
        #expect(EvaluationStatus.verifying.rawValue == "verifying")
        #expect(VerdictMethod.check.rawValue == "check")
    }
}
