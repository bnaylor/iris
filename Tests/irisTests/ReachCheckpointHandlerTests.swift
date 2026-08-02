import Testing
import Foundation
@testable import iris

private func reachCheckpointResponse(summary: String) -> GeminiResponse {
    let call = FunctionCall(name: "reach_checkpoint",
                            args: ["milestone_summary": .string(summary)],
                            id: nil, thought_signature: nil, thoughtSignature: nil)
    let part = Part(text: nil, functionCall: call, functionResponse: nil,
                    thought_signature: nil, thoughtSignature: nil)
    return GeminiResponse(candidates: [Candidate(content: Content(role: "model", parts: [part]))],
                          usageMetadata: nil)
}

// A grader response that submits an empty evaluation, so GoalEvaluator resolves quickly.
private func submitEvaluationResponse() -> GeminiResponse {
    let call = FunctionCall(name: "submit_evaluation",
                            args: ["evaluations": .array([])],
                            id: nil, thought_signature: nil, thoughtSignature: nil)
    let part = Part(text: nil, functionCall: call, functionResponse: nil,
                    thought_signature: nil, thoughtSignature: nil)
    return GeminiResponse(candidates: [Candidate(content: Content(role: "model", parts: [part]))],
                          usageMetadata: nil)
}

@MainActor
@Suite("reach_checkpoint handler")
struct ReachCheckpointHandlerTests {
    private func lockLadder(on app: AppState, _ id: UUID) {
        app.createNewConversation(id: id)
        let a = Criterion(text: "build", kind: .qualitative, check: nil)
        let b = Criterion(text: "docs", kind: .qualitative, check: nil)
        var c = GoalContract(objective: "Ship", criteria: [a, b])
        c.milestones = [Milestone(title: "One", criterionIds: [a.id]),
                        Milestone(title: "Two", criterionIds: [b.id])]
        app.setGoalContract(for: id, c)
    }

    @Test("reach_checkpoint pauses without clearing the goal and records an evaluation")
    func pausesAndGrades() async {
        let app = AppState(); let id = UUID(); lockLadder(on: app, id)
        // First the working agent calls reach_checkpoint; then the grader (fresh convo) submits.
        let mock = ScriptedLLMClient(responses: [
            reachCheckpointResponse(summary: "milestone one done"),
            submitEvaluationResponse(),
        ])
        let engine = IrisEngine(state: app, tier: .medium, principal: .main, client: mock)
        await engine.processInput("work", source: "User", conversationId: id)

        let conv = app.conversations.first { $0.id == id }
        #expect(conv?.goalContract?.checkpointStatus == .pausedForReview)
        #expect(conv?.activeGoal != nil)                      // NOT cleared (contrast goal_complete)
        #expect(conv?.goalContract?.currentMilestone == 0)    // not advanced by the handler
        #expect(conv?.lastGoalEvaluation != nil)              // a grade landed
    }
}
