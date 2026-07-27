import Testing
import Foundation
@testable import iris

/// A scripted LLM client: returns queued responses in order without any network call,
/// and records how many times it was asked (to prove single-round behavior).
final class ScriptedLLMClient: LLMClientProtocol, @unchecked Sendable {
    private var index = 0
    private(set) var callCount = 0
    private let responses: [GeminiResponse]

    init(responses: [GeminiResponse]) { self.responses = responses }

    // The engine awaits each turn before the next, so calls are serialized — no lock needed.
    func generateContent(request: GeminiRequest, tier: ModelTier) async throws -> GeminiResponse {
        callCount += 1
        let response = responses[min(index, responses.count - 1)]
        index += 1
        return response
    }
}

private func runCommandResponse(_ command: String) -> GeminiResponse {
    let call = FunctionCall(name: "run_command", args: ["command": .string(command)],
                            id: nil, thought_signature: nil, thoughtSignature: nil)
    let part = Part(text: nil, functionCall: call, functionResponse: nil,
                    thought_signature: nil, thoughtSignature: nil)
    return GeminiResponse(candidates: [Candidate(content: Content(role: "model", parts: [part]))],
                          usageMetadata: nil)
}

@MainActor
@Suite("Loop-stop enforcement")
struct LoopStopEnforcementTests {

    /// Regression guard for #16: when loop detection stops a goal, the follow-up summary turn
    /// runs with `restrictToGoalComplete`. Removing the tool from the schema is NOT enough — the
    /// model can still emit the call and the dispatcher would execute any named tool — so the
    /// execution layer must block anything but `goal_complete`. Here the model keeps trying to
    /// call `run_command`; the block must fire and the turn must not spin.
    @Test("restricted turn blocks a non-goal_complete tool and runs a single round")
    func restrictedTurnBlocksTool() async {
        let appState = AppState()
        let convId = UUID()
        appState.createNewConversation(id: convId)

        // Two identical run_command responses queued. If the engine honored the second one, the
        // turn spun; a correct single-round turn only asks the model once.
        let mock = ScriptedLLMClient(responses: [
            runCommandResponse("echo stuck"),
            runCommandResponse("echo stuck"),
        ])
        let engine = IrisEngine(state: appState, tier: .medium, client: mock)

        await engine.processInput("You reached a stopping condition. Summarize and stop.",
                                  source: "System", conversationId: convId,
                                  restrictToGoalComplete: true)

        let messages = appState.conversations.first(where: { $0.id == convId })?.messages ?? []

        // The block fired: a system message names the blocked tool, and it never executed.
        #expect(messages.contains {
            $0.content.contains("[blocked]") && $0.content.contains("run_command")
        })
        // The looping tool never ran, so no [TOOL_CALL] execution notice was emitted for it.
        #expect(!messages.contains { $0.content.contains("[TOOL_CALL]") })
        // Single round: the engine asked the model exactly once and did not reprompt itself.
        #expect(mock.callCount == 1)
    }
}
