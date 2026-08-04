import Foundation

final class SubagentManager: @unchecked Sendable {
    static let shared = SubagentManager()
    
    private let lock = NSLock()
    private weak var _state: AppState?
    
    var state: AppState? {
        get { lock.withLock { _state } }
        set { lock.withLock { _state = newValue } }
    }
    
    private init() {}
    
    func setGlobalState(_ state: AppState) {
        self.state = state
    }
    
    func runSubagent(role: String, task: String, effort: String, parentConversationId: UUID, maxIterations: Int = 3000) async -> String {
        guard let appState = self.state else {
            return "Error: AppState not available for subagent execution."
        }

        let startedAt = Date()

        // 1. Create a new conversation for the subagent
        let subagentId = UUID()
        await MainActor.run {
            appState.createNewConversation(id: subagentId, isSubagent: true)
            appState.updateConversationTitle(id: subagentId, title: "Subagent: \(role)")
            appState.registerSubagent(id: subagentId, role: role)
        }

        let tier: ModelTier
        switch effort.lowercased() {
        case "easy": tier = .easy
        case "hard": tier = .hard
        default: tier = .medium
        }

        // 2. Instantiate a fresh IrisEngine linked to this conversation
        let engine = IrisEngine(state: appState, tier: tier, principal: .subagent, roleLabel: role)

        // 3. Craft the role-specific prompt
        let customPromptText = generateRolePrompt(role: role)
        await engine.setSystemPrompt(text: customPromptText)

        // 4. Inject the initial task and set the goal so the engine auto-loops
        await MainActor.run {
            appState.setGoal(for: subagentId, goal: task)
            appState.appendMessage(role: .system, content: "Starting subagent with role '\(role)' to execute task:\n\(task)", to: subagentId)
        }

        actor ResultHolder {
            var termination: SubagentTermination? = nil
            func set(_ t: SubagentTermination) { if termination == nil { termination = t } }
            func get() -> SubagentTermination? { return termination }
        }
        let holder = ResultHolder()

        await MainActor.run {
            appState.onSubagentComplete[subagentId] = { termination in
                Task { await holder.set(termination) }
                Task { @MainActor in appState.onSubagentComplete[subagentId] = nil }
            }
        }

        let engineTask = Task {
            // Kick off the first turn. Since activeGoal is set, the engine will autonomously reprompt itself
            // in a loop until goal_complete is called.
            await engine.processInput(task, source: "System", conversationId: subagentId)
        }

        var iterations = 0
        while await holder.get() == nil {
            if iterations >= maxIterations {
                // Hard stop: cancel the engine task, unstick any pending approval, stop the
                // reprompt loop, free the sandbox container, and clear the goal.
                engineTask.cancel()
                await MainActor.run { appState.denyPendingApprovals(for: subagentId) }
                await engine.cancelReprompt(for: subagentId)
                await SandboxSessionManager.shared.endSession(subagentId)
                await MainActor.run { appState.clearGoal(for: subagentId) }
                await holder.set(SubagentTermination(status: .timedOut,
                    summary: "Subagent timed out after the iteration cap and was cancelled (task, pending approvals, and sandbox container cleaned up).",
                    calledGoalComplete: false))
                break
            }
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            iterations += 1
        }
        let termination = await holder.get() ?? SubagentTermination(status: .failed, summary: "Subagent completed with no summary.", calledGoalComplete: false)
        let files = await MainActor.run { appState.drainSubagentWrites(for: subagentId) }
        let result = SubagentResult(role: role, status: termination.status,
                                    calledGoalComplete: termination.calledGoalComplete,
                                    summary: termination.summary, filesWritten: files,
                                    startedAt: startedAt, endedAt: Date())
        await MainActor.run {
            appState.setSubagentResult(for: subagentId, result)
            appState.removeSubagent(id: subagentId)
        }
        return result.renderedForParent()
    }
    
    func generateRolePrompt(role: String) -> String {
        let base = "You are Iris, operating in a specialized subagent role: **\(role.uppercased())**.\n" +
                   "You are executing within a fully configurable sandboxed micro-VM. You have full root permissions inside this VM environment to install packages, configure tools, and run commands needed to complete your objective.\n\n"
        var specific = ""
        
        switch role.lowercased() {
        case "code_reviewer":
            specific = "Your goal is to review code. Look for bugs, architectural flaws, and style issues. Do not write new features. Be critical and precise."
        case "security_auditor":
            specific = "Your goal is to audit code for security vulnerabilities. Look for prompt injections, path traversals, XSS, and weak cryptography."
        case "researcher":
            specific = "Your goal is to gather context. Use search_web and read_file heavily. Summarize your findings accurately. Do not mutate any files."
        case "engineer":
            specific = "Your goal is to implement a specific component using TDD. Write failing tests first, then implement. Do not modify unrelated code."
        default:
            specific = "Your goal is to execute the assigned task efficiently and autonomously."
        }
        
        return base + specific + "\n\nWhen you are finished, you MUST call the `goal_complete` tool with a summary of your findings to return control to the parent agent."
    }
}
