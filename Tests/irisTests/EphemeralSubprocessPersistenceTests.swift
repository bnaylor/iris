import Testing
import Foundation
@testable import iris

@Suite("Ephemeral sub-process persistence")
struct EphemeralSubprocessPersistenceTests {
    private func conv(_ title: String, isSubagent: Bool) -> Conversation {
        var c = Conversation(id: UUID(), title: title)
        c.isSubagent = isSubagent
        return c
    }

    @Test("durableConversations drops subagent/evaluator scratch conversations")
    func durableFilters() {
        let all = [conv("main", isSubagent: false),
                   conv("Evaluator", isSubagent: true),
                   conv("Subagent: coder", isSubagent: true)]
        let durable = AppState.durableConversations(all)
        #expect(durable.count == 1)
        #expect(durable.first?.title == "main")
    }

    @Test("sanitizeLoaded purges orphaned sub-process conversations from old data")
    func loadPurgesOrphans() {
        let decoded = [conv("main", isSubagent: false), conv("Evaluator", isSubagent: true)]
        let loaded = AppState.sanitizeLoaded(decoded)
        #expect(loaded.map { $0.isSubagent } == [false])   // only the durable one survives
    }

    @Test("sanitizeLoaded settles a still-verifying evaluation to failed")
    func loadSettlesVerifying() {
        var main = conv("main", isSubagent: false)
        main.lastGoalEvaluation = GoalEvaluation(
            status: .verifying,
            criteria: [CriterionVerdict(criterionId: UUID(), criterionText: "c", kind: .qualitative,
                                        verdict: .cannotVerify, evidence: "", method: .judge)],
            startedAt: Date(timeIntervalSince1970: 100), completedAt: nil)
        let loaded = AppState.sanitizeLoaded([main])
        #expect(loaded.first?.lastGoalEvaluation?.status == .failed)
        #expect(loaded.first?.lastGoalEvaluation?.completedAt != nil)
    }

    @Test("sanitizeLoaded leaves a graded evaluation untouched")
    func loadKeepsGraded() {
        var main = conv("main", isSubagent: false)
        let done = Date(timeIntervalSince1970: 200)
        main.lastGoalEvaluation = GoalEvaluation(
            status: .graded,
            criteria: [CriterionVerdict(criterionId: UUID(), criterionText: "c", kind: .executable,
                                        verdict: .met, evidence: "exit 0", method: .check)],
            startedAt: Date(timeIntervalSince1970: 100), completedAt: done)
        let loaded = AppState.sanitizeLoaded([main])
        #expect(loaded.first?.lastGoalEvaluation?.status == .graded)
        #expect(loaded.first?.lastGoalEvaluation?.completedAt == done)
    }
}
