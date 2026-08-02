import Testing
import Foundation
@testable import iris

@Suite("GoalContract ladder")
struct GoalContractLadderTests {
    private func laddered() -> GoalContract {
        let a = Criterion(text: "build green", kind: .executable, check: "swift build")
        let b = Criterion(text: "tests pass", kind: .executable, check: "swift test")
        let c = Criterion(text: "docs updated", kind: .qualitative, check: nil)
        var contract = GoalContract(objective: "Ship it", criteria: [a, b, c])
        contract.milestones = [
            Milestone(title: "Compile", criterionIds: [a.id]),
            Milestone(title: "Verify", criterionIds: [b.id, c.id]),
        ]
        return contract
    }

    @Test("hasLadder and isFinalMilestone reflect the ladder")
    func flags() {
        var c = laddered()
        #expect(c.hasLadder)
        #expect(!c.isFinalMilestone)          // currentMilestone == 0, two milestones
        c.currentMilestone = 1
        #expect(c.isFinalMilestone)
        let empty = GoalContract(objective: "x", criteria: [])
        #expect(!empty.hasLadder)
    }

    @Test("currentMilestoneCriteria returns only the current milestone's criteria")
    func currentSlice() {
        let c = laddered()
        #expect(c.currentMilestoneCriteria().map(\.text) == ["build green"])
    }

    @Test("projectedContract is cumulative through N, locked, and de-laddered")
    func projection() {
        let c = laddered()
        let p0 = c.projectedContract(throughMilestone: 0)
        #expect(p0.criteria.map(\.text) == ["build green"])
        #expect(p0.milestones.isEmpty)
        #expect(p0.isLocked)
        let p1 = c.projectedContract(throughMilestone: 1)
        #expect(p1.criteria.map(\.text) == ["build green", "tests pass", "docs updated"])
    }

    @Test("ladderIsValidPartition accepts a disjoint cover and rejects a gap")
    func partition() {
        #expect(laddered().ladderIsValidPartition())
        var gap = laddered()
        gap.milestones = [gap.milestones[0]]     // drops criteria b and c
        #expect(!gap.ladderIsValidPartition())
        #expect(GoalContract(objective: "x", criteria: []).ladderIsValidPartition())  // no ladder is valid
    }

    @Test("normalizedLadder folds unassigned criteria into a final milestone and clamps index")
    func normalize() {
        var gap = laddered()
        gap.milestones = [gap.milestones[0]]     // b and c now unassigned
        gap.currentMilestone = 9
        let n = gap.normalizedLadder()
        #expect(n.milestones.count == 2)
        #expect(n.milestones.last?.criterionIds.count == 2)   // b and c folded in
        #expect(n.currentMilestone == 1)                       // clamped to last index
    }

    @Test("ladder round-trips through Codable and legacy contracts decode to no ladder")
    func codable() throws {
        var c = laddered(); c.lock()
        let back = try JSONDecoder().decode(GoalContract.self, from: JSONEncoder().encode(c))
        #expect(back == c)
        // A contract encoded without ladder fields (simulated by a plain contract) has an empty ladder.
        let legacy = GoalContract(objective: "old", criteria: [Criterion(text: "y", kind: .qualitative, check: nil)])
        let legacyBack = try JSONDecoder().decode(GoalContract.self, from: JSONEncoder().encode(legacy))
        #expect(!legacyBack.hasLadder)
        #expect(legacyBack.checkpointStatus == .running)
    }
}
