import Foundation

final class SubagentManager: @unchecked Sendable {
    static let shared = SubagentManager()
    
    // We can hold weak reference to the global app state, or a standalone state
    weak var state: AppState?
    
    private init() {}
    
    func setGlobalState(_ state: AppState) {
        self.state = state
    }
    
    func runSubagent(role: String, task: String, effort: String, parentConversationId: UUID) async -> String {
        guard let appState = state else {
            return "Error: AppState not available for subagent execution."
        }
        
        // 1. Create a new conversation for the subagent
        let subagentId = UUID()
        await MainActor.run {
            appState.createNewConversation(id: subagentId)
            appState.updateConversationTitle(id: subagentId, title: "Subagent: \(role)")
        }
        
        let tier: ModelTier
        switch effort.lowercased() {
        case "easy": tier = .easy
        case "hard": tier = .hard
        default: tier = .medium
        }
        
        // 2. Instantiate a fresh IrisEngine linked to this conversation
        let engine = IrisEngine(state: appState, tier: tier)
        
        // 3. Craft the role-specific prompt
        let customPromptText = generateRolePrompt(role: role)
        await engine.setSystemPrompt(text: customPromptText)
        
        // 4. Inject the initial task
        await MainActor.run {
            appState.appendMessage(role: .system, content: "Starting subagent with role '\(role)' to execute task:\n\(task)", to: subagentId)
        }
        
        actor ResultHolder {
            var summary: String? = nil
            func setSummary(_ s: String) { summary = s }
            func getSummary() -> String? { return summary }
        }
        let holder = ResultHolder()
        
        await MainActor.run {
            appState.onSubagentComplete = { [weak holder] id, sum in
                if id == subagentId {
                    Task { await holder?.setSummary(sum) }
                }
            }
        }
        
        // Kick off the first turn
        await engine.processInput(task, source: "System", conversationId: subagentId)
        
        if let finalSummary = await holder.getSummary() {
            return finalSummary
        }
        return "Subagent finished without calling goal_complete."
    }
    
    private func generateRolePrompt(role: String) -> String {
        let base = "You are Iris, operating in a specialized subagent role: **\(role.uppercased())**.\n\n"
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
