import Testing
import Foundation
@testable import iris

@Suite("GoalEvaluation parsing")
struct GoalEvaluationParsingTests {
    private func criteria() -> [Criterion] {
        [Criterion(text: "build", kind: .executable, check: "swift build"),
         Criterion(text: "playable", kind: .qualitative, check: nil),
         Criterion(text: "tasteful", kind: .humanJudged, check: nil)]
    }

    @Test("maps submitted verdicts to the right criteria by id")
    func maps() {
        let c = criteria()
        let args: [String: JSONValue] = ["evaluations": .array([
            .object(["criterion_id": .string(c[0].id.uuidString), "verdict": .string("met"), "evidence": .string("exit 0")]),
            .object(["criterion_id": .string(c[1].id.uuidString), "verdict": .string("not_met"), "evidence": .string("crashes on start")])
        ])]
        let out = GoalEvaluationParsing.verdicts(from: args, criteria: c)
        #expect(out.count == 3)
        #expect(out.first { $0.criterionId == c[0].id }?.verdict == .met)
        #expect(out.first { $0.criterionId == c[0].id }?.method == .check)     // executable → check
        #expect(out.first { $0.criterionId == c[1].id }?.verdict == .notMet)
        #expect(out.first { $0.criterionId == c[1].id }?.method == .judge)     // qualitative → judge
    }

    @Test("an omitted humanJudged criterion becomes humanPending, other omissions cannot_verify")
    func reconciliation() {
        let c = criteria()
        // Only the executable criterion is reported; the other two are omitted.
        let args: [String: JSONValue] = ["evaluations": .array([
            .object(["criterion_id": .string(c[0].id.uuidString), "verdict": .string("met"), "evidence": .string("ok")])
        ])]
        let out = GoalEvaluationParsing.verdicts(from: args, criteria: c)
        #expect(out.first { $0.criterionId == c[1].id }?.verdict == .cannotVerify)   // qualitative omitted
        #expect(out.first { $0.criterionId == c[2].id }?.verdict == .humanPending)   // humanJudged omitted
        #expect(out.first { $0.criterionId == c[2].id }?.method == .human)
    }

    @Test("an unknown verdict string falls back to cannot_verify")
    func unknownVerdict() {
        let c = criteria()
        let args: [String: JSONValue] = ["evaluations": .array([
            .object(["criterion_id": .string(c[0].id.uuidString), "verdict": .string("bogus"), "evidence": .string("")])
        ])]
        let out = GoalEvaluationParsing.verdicts(from: args, criteria: c)
        #expect(out.first { $0.criterionId == c[0].id }?.verdict == .cannotVerify)
    }
}
