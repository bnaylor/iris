import Testing
import Foundation
@testable import iris

@Suite("GoalContract")
struct GoalContractTests {
    private func draft() -> GoalContract {
        GoalContract(objective: "Fix the reflow",
                     criteria: [Criterion(text: "swift build green", kind: .executable, check: "swift build"),
                                Criterion(text: "twisty repaints without scroll", kind: .qualitative, check: nil)])
    }

    @Test("round-trips through Codable")
    func codable() throws {
        var c = draft(); c.lock()
        let data = try JSONEncoder().encode(c)
        let back = try JSONDecoder().decode(GoalContract.self, from: data)
        #expect(back == c)
    }

    @Test("lock flips state and isLocked")
    func locking() {
        var c = draft()
        #expect(!c.isLocked)
        c.lock()
        #expect(c.isLocked && c.state == .locked)
    }

    @Test("a draft edit does not require a rationale and does not log")
    func draftEdit() {
        var c = draft()
        let ok = c.applyCriteriaEdit(rationale: "") { $0.append(Criterion(text: "x", kind: .qualitative, check: nil)) }
        #expect(ok)
        #expect(c.criteria.count == 3)
        #expect(c.changeLog.isEmpty)
    }

    @Test("a locked edit without a rationale is rejected and changes nothing")
    func lockedEditNoRationale() {
        var c = draft(); c.lock()
        let ok = c.applyCriteriaEdit(rationale: "   ") { $0.removeAll() }
        #expect(!ok)
        #expect(c.criteria.count == 2)   // unchanged
        #expect(c.changeLog.isEmpty)
    }

    @Test("a locked edit with a rationale applies and appends a change-log entry")
    func lockedEditWithRationale() {
        var c = draft(); c.lock()
        let ok = c.applyCriteriaEdit(rationale: "criterion was wrong") {
            $0.append(Criterion(text: "new", kind: .qualitative, check: nil))
        }
        #expect(ok)
        #expect(c.criteria.count == 3)
        #expect(c.changeLog.count == 1)
        #expect(c.changeLog.first?.rationale == "criterion was wrong")
    }

    @Test("oracleText includes objective, each criterion, out-of-scope, stop-before")
    func oracle() {
        var c = draft()
        c.outOfScope = ["selection refactor"]; c.stopBefore = ["force-push"]
        let t = c.oracleText()
        #expect(t.contains("Fix the reflow"))
        #expect(t.contains("swift build green"))
        #expect(t.contains("selection refactor"))
        #expect(t.contains("force-push"))
    }
}
