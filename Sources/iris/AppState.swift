import Foundation
import SwiftUI

enum ChatRole: String, Codable {
    case user
    case agent
    case system
}

struct ChatMessage: Identifiable, Codable {
    var id = UUID()
    let role: ChatRole
    let content: String
}

struct TokenUsage: Codable, Equatable {
    var promptTokenCount: Int = 0
    var candidatesTokenCount: Int = 0
    var totalTokenCount: Int = 0
}

struct Conversation: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var messages: [ChatMessage] = []
    var workspacePath: String?
    var history: [Content] = []
    var tokenUsage: TokenUsage = TokenUsage()
    var activeGoal: String?
    var messageCountSinceReflection: Int = 0
    
    static func == (lhs: Conversation, rhs: Conversation) -> Bool {
        lhs.id == rhs.id
    }
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct ToolApprovalRequest: Identifiable {
    let id = UUID()
    let toolName: String
    let details: String
    let continuation: CheckedContinuation<Bool, Never>
}

@MainActor
@Observable
class AppState {
    var conversations: [Conversation] = []
    var selectedConversationId: UUID?
    var isThinking = false
    var pendingApproval: ToolApprovalRequest?
    
    private var engine: IrisEngine!
    
    init() {
        self.engine = IrisEngine(state: self)
        loadConversations()
        if conversations.isEmpty {
            createNewConversation()
        }
    }
    
    var activeConversationIndex: Int? {
        conversations.firstIndex(where: { $0.id == selectedConversationId })
    }
    
    func createNewConversation() {
        let newConv = Conversation(title: "New Conversation")
        conversations.append(newConv)
        selectedConversationId = newConv.id
        saveConversations()
    }
    
    func setWorkspace(for conversationId: UUID, path: String) {
        if let idx = conversations.firstIndex(where: { $0.id == conversationId }) {
            conversations[idx].workspacePath = path
            saveConversations()
        }
    }
    
    func deleteConversation(_ id: UUID) {
        conversations.removeAll { $0.id == id }
        if selectedConversationId == id {
            selectedConversationId = conversations.last?.id
        }
        if conversations.isEmpty {
            createNewConversation()
        } else {
            saveConversations()
        }
    }
    
    func start() {
        Task {
            await engine.start()
        }
    }
    
    func sendMessage(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let convId = selectedConversationId else { return }
        
        var messageContent = trimmed
        if trimmed.hasPrefix("/goal") {
            let goalText = trimmed.dropFirst(5).trimmingCharacters(in: .whitespacesAndNewlines)
            if goalText.isEmpty {
                appendMessage(role: .system, content: "Please specify a goal, e.g., `/goal Build a snake game in Python`", to: convId)
                return
            }
            if let idx = conversations.firstIndex(where: { $0.id == convId }) {
                conversations[idx].activeGoal = goalText
                saveConversations()
            }
            messageContent = "GOAL MODE ACTIVATED. Your goal is: \(goalText). You must continually use tools to achieve this goal. If you need to stop and think or plan, use the `reflect` tool or just output text. When the goal is COMPLETELY FINISHED, use the `goal_complete` tool."
        } else if trimmed.hasPrefix("/stop") {
            if let idx = conversations.firstIndex(where: { $0.id == convId }) {
                conversations[idx].activeGoal = nil
                saveConversations()
            }
            appendMessage(role: .system, content: "Goal mode cancelled.", to: convId)
            return
        } else if trimmed.hasPrefix("/reflect") {
            appendMessage(role: .system, content: "Triggering manual memory reflection...", to: convId)
            isThinking = true
            let reflectionPrompt = """
            System Event [Reflection Trigger]: It's time to consolidate your memories. Reflect on the recent conversation. Have you learned any new user preferences, project structures, or recurring workflows? If so, use `write_file` or `read_file` to update `~/.iris/skills/`, `update_user_profile` to update `USER.md`, or update your core `SOUL.md`. 
            
            Additionally, perform a grooming pass on your Markdown memory library. Ensure ALL memory files (`~/.iris/skills/*`, `USER.md`, `SOUL.md`) use the Open Knowledge Format (OKF). This means each file MUST start with a YAML frontmatter block containing at least:
            ---
            type: [skill|profile|core|etc]
            title: ...
            description: ...
            tags: [..., ...]
            timestamp: ...
            ---
            Verify that your cross-links between files are still valid, and reorganize or fix any broken links. Output a transparent summary of the gist of the updates and grooming performed for the user. If nothing needs updating, just reply 'No memory consolidation needed at this time.'
            """
            Task {
                await engine.processInput(reflectionPrompt, source: "System", conversationId: convId)
                isThinking = false
            }
            return
        } else if trimmed.hasPrefix("/vibecop init") {
            appendMessage(role: .system, content: "Initializing Vibecop Guardian mode...", to: convId)
            isThinking = true
            let initPrompt = "System Event [Vibecop Init]: Analyze the current workspace directory to understand the project structure, language, framework, and tooling. Generate a custom Guardian prompt that defines what terminal commands and file operations are 'routine' for this specific workspace, and what should be escalated to the user. Write this prompt to a new file at `.iris/vibecop.md` inside the workspace using the `write_file` tool. Output a transparent summary of the generated rules for the user."
            Task {
                await engine.processInput(initPrompt, source: "System", conversationId: convId)
                isThinking = false
            }
            return
        }
        
        appendMessage(role: .user, content: messageContent, to: convId)
        isThinking = true
        
        if let idx = conversations.firstIndex(where: { $0.id == convId }) {
            conversations[idx].messageCountSinceReflection += 1
            saveConversations()
            
            let shouldReflect = conversations[idx].messageCountSinceReflection >= 30
            if shouldReflect {
                conversations[idx].messageCountSinceReflection = 0
                saveConversations()
                
                // We'll queue the reflection system message after the current task finishes.
                Task {
                    await engine.processInput(messageContent, source: "UI", conversationId: convId)
                    
                    let reflectionPrompt = "System Event [Reflection Trigger]: It's time to consolidate your memories. Reflect on the recent conversation. Have you learned any new user preferences, project structures, or recurring workflows? If so, use `write_file` or `read_file` to update `~/.iris/skills/`, `update_user_profile` to update `USER.md`, or update your core `SOUL.md`. Output a transparent summary of the gist of the updates for the user. If nothing needs updating, just reply 'No memory consolidation needed at this time.'"
                    appendMessage(role: .system, content: "Triggering automatic memory reflection...", to: convId)
                    isThinking = true
                    await engine.processInput(reflectionPrompt, source: "System", conversationId: convId)
                    isThinking = false
                }
            } else {
                Task {
                    await engine.processInput(messageContent, source: "UI", conversationId: convId)
                    isThinking = false
                }
            }
        } else {
            Task {
                await engine.processInput(messageContent, source: "UI", conversationId: convId)
                isThinking = false
            }
        }
    }
    
    func appendMessage(role: ChatRole, content: String, to conversationId: UUID) {
        if let idx = conversations.firstIndex(where: { $0.id == conversationId }) {
            conversations[idx].messages.append(ChatMessage(role: role, content: content))
            
            // Auto-title generation based on first message
            if role == .user && conversations[idx].messages.filter({ $0.role == .user }).count == 1 {
                conversations[idx].title = String(content.prefix(30)) + (content.count > 30 ? "..." : "")
            }
            saveConversations()
        }
    }
    
    func updateHistory(for conversationId: UUID, history: [Content]) {
        if let idx = conversations.firstIndex(where: { $0.id == conversationId }) {
            conversations[idx].history = history
            saveConversations()
        }
    }
    
    func updateTokenUsage(for conversationId: UUID, usage: UsageMetadata) {
        if let idx = conversations.firstIndex(where: { $0.id == conversationId }) {
            conversations[idx].tokenUsage.promptTokenCount += usage.promptTokenCount ?? 0
            conversations[idx].tokenUsage.candidatesTokenCount += usage.candidatesTokenCount ?? 0
            conversations[idx].tokenUsage.totalTokenCount += usage.totalTokenCount ?? 0
            saveConversations()
        }
    }
    
    func clearGoal(for conversationId: UUID) {
        if let idx = conversations.firstIndex(where: { $0.id == conversationId }) {
            conversations[idx].activeGoal = nil
            saveConversations()
        }
    }
    
    func requestApproval(toolName: String, details: String, workspace: String? = nil) async -> Bool {
        do {
            let decision = try await VibecopService.shared.evaluateAction(toolName: toolName, details: details, workspace: workspace)
            if decision.decision == "APPROVE" {
                return true
            } else if decision.decision == "DENY" {
                return false
            }
            // If ESCALATE, fall through to user prompt
        } catch {
            // If Vibecop fails, fail open to the user prompt
            print("Vibecop evaluation failed: \(error)")
        }
        
        return await withCheckedContinuation { continuation in
            self.pendingApproval = ToolApprovalRequest(toolName: toolName, details: details, continuation: continuation)
        }
    }
    
    func resolveApproval(_ approved: Bool) {
        let cont = pendingApproval?.continuation
        pendingApproval = nil
        cont?.resume(returning: approved)
    }
    
    private func saveConversations() {
        if let data = try? JSONEncoder().encode(conversations) {
            UserDefaults.standard.set(data, forKey: "iris_conversations")
        }
    }
    
    private func loadConversations() {
        if let data = UserDefaults.standard.data(forKey: "iris_conversations"),
           let decoded = try? JSONDecoder().decode([Conversation].self, from: data) {
            self.conversations = decoded
            self.selectedConversationId = decoded.last?.id
        }
    }
}
