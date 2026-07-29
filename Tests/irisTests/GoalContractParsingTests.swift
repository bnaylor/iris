import Testing
@testable import iris

@Suite("GoalContract parsing")
struct GoalContractParsingTests {
    @Test("builds a draft contract from a tool-call args payload")
    func parses() {
        let args: [String: JSONValue] = [
            "objective": .string("Fix the reflow"),
            "criteria": .array([
                .object(["text": .string("swift build green"), "kind": .string("executable"), "check": .string("swift build")]),
                .object(["text": .string("repaints without scroll"), "kind": .string("qualitative")])
            ]),
            "out_of_scope": .array([.string("selection refactor")]),
            "stop_before": .array([.string("force-push")]),
            "assumptions": .array([.string("keep the List container")])
        ]
        let c = GoalContractParsing.contract(from: args)
        #expect(c?.objective == "Fix the reflow")
        #expect(c?.state == .draft)
        #expect(c?.criteria.count == 2)
        #expect(c?.criteria.first?.kind == .executable)
        #expect(c?.criteria.first?.check == "swift build")
        #expect(c?.criteria.last?.check == nil)
        #expect(c?.outOfScope == ["selection refactor"])
        #expect(c?.stopBefore == ["force-push"])
    }

    @Test("an unknown kind falls back to qualitative")
    func unknownKind() {
        let args: [String: JSONValue] = [
            "objective": .string("x"),
            "criteria": .array([.object(["text": .string("c"), "kind": .string("bogus")])])
        ]
        #expect(GoalContractParsing.contract(from: args)?.criteria.first?.kind == .qualitative)
    }

    @Test("missing objective returns nil")
    func noObjective() {
        #expect(GoalContractParsing.contract(from: ["criteria": .array([])]) == nil)
    }
}
