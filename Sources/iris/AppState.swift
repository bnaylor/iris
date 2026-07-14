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
    var goalIterationCount: Int = 0
    
    init(id: UUID = UUID(), title: String, messages: [ChatMessage] = [], workspacePath: String? = nil, history: [Content] = [], tokenUsage: TokenUsage = TokenUsage(), activeGoal: String? = nil, messageCountSinceReflection: Int = 0) {
        self.id = id
        self.title = title
        self.messages = messages
        self.workspacePath = workspacePath
        self.history = history
        self.tokenUsage = tokenUsage
        self.activeGoal = activeGoal
        self.messageCountSinceReflection = messageCountSinceReflection
    }
    
    enum CodingKeys: String, CodingKey {
        case id, title, messages, workspacePath, history, tokenUsage, activeGoal, messageCountSinceReflection
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try container.decode(String.self, forKey: .title)
        messages = try container.decodeIfPresent([ChatMessage].self, forKey: .messages) ?? []
        workspacePath = try container.decodeIfPresent(String.self, forKey: .workspacePath)
        history = try container.decodeIfPresent([Content].self, forKey: .history) ?? []
        tokenUsage = try container.decodeIfPresent(TokenUsage.self, forKey: .tokenUsage) ?? TokenUsage()
        activeGoal = try container.decodeIfPresent(String.self, forKey: .activeGoal)
        messageCountSinceReflection = try container.decodeIfPresent(Int.self, forKey: .messageCountSinceReflection) ?? 0
    }
    
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
    let workspace: String?
    let continuation: CheckedContinuation<Bool, Never>
}

struct ActiveSubagent: Identifiable, Hashable {
    let id: UUID
    let role: String
    let startTime: Date
    var status: String
}

@MainActor
@Observable
class AppState {
    var conversations: [Conversation] = []
    var selectedConversationId: UUID?
    var isThinking = false
    var activeSubagents: [ActiveSubagent] = []
    var pendingApproval: ToolApprovalRequest?
    var onSubagentComplete: [UUID: @Sendable (String) -> Void] = [:]
    
    private var engine: IrisEngine!
    
    init() {
        self.engine = IrisEngine(state: self)
        SubagentManager.shared.setGlobalState(self)
        loadConversations()
        if conversations.isEmpty {
            createNewConversation()
        }
    }
    
    var activeConversationIndex: Int? {
        conversations.firstIndex(where: { $0.id == selectedConversationId })
    }
    
    func createNewConversation(id: UUID = UUID()) {
        let newConv = Conversation(id: id, title: "New Conversation")
        conversations.append(newConv)
        selectedConversationId = newConv.id
        saveConversations()
        
        Task {
            _ = await HookManager.shared.fireSessionStart(conversationId: newConv.id)
        }
    }
    
    func updateConversationTitle(id: UUID, title: String) {
        if let idx = conversations.firstIndex(where: { $0.id == id }) {
            conversations[idx].title = title
            saveConversations()
        }
    }
    
    func registerSubagent(id: UUID, role: String) {
        let subagent = ActiveSubagent(id: id, role: role, startTime: Date(), status: "Initializing...")
        activeSubagents.append(subagent)
    }
    
    func removeSubagent(id: UUID) {
        activeSubagents.removeAll(where: { $0.id == id })
    }
    
    func updateSubagentStatus(id: UUID, status: String) {
        if let idx = activeSubagents.firstIndex(where: { $0.id == id }) {
            activeSubagents[idx].status = status
        }
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
        } else if trimmed.hasPrefix("/rename") {
            appendMessage(role: .system, content: "Triggering automatic conversation rename...", to: convId)
            isThinking = true
            let renamePrompt = "System Event [Rename Trigger]: Evaluate the conversation history and use the `rename_conversation` tool to assign a short, descriptive title (1-4 words) that captures the true gist of this conversation."
            Task {
                await engine.processInput(renamePrompt, source: "System", conversationId: convId)
                isThinking = false
            }
            return
        }
        
        appendMessage(role: .user, content: messageContent, to: convId)
        isThinking = true
        
        if let idx = conversations.firstIndex(where: { $0.id == convId }) {
            conversations[idx].messageCountSinceReflection += 1
            saveConversations()
            
            let userMessagesCount = conversations[idx].messages.filter { $0.role == .user }.count
            let shouldRename = userMessagesCount == 3 && conversations[idx].messageCountSinceReflection == 3
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
            } else if shouldRename {
                Task {
                    await engine.processInput(messageContent, source: "UI", conversationId: convId)
                    
                    let renamePrompt = "System Event [Rename Trigger]: Evaluate the conversation history and use the `rename_conversation` tool to assign a short, descriptive title (1-4 words) that captures the true gist of this conversation."
                    appendMessage(role: .system, content: "Triggering automatic conversation rename...", to: convId)
                    isThinking = true
                    await engine.processInput(renamePrompt, source: "System", conversationId: convId)
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
    
    func appendContentToHistory(for conversationId: UUID, content: Content) {
        if let idx = conversations.firstIndex(where: { $0.id == conversationId }) {
            conversations[idx].history.append(content)
            saveConversations()
        }
    }
    
    func appendContentsToHistory(for conversationId: UUID, contents: [Content]) {
        if let idx = conversations.firstIndex(where: { $0.id == conversationId }) {
            conversations[idx].history.append(contentsOf: contents)
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
            conversations[idx].goalIterationCount = 0
            saveConversations()
        }
    }
    
    func setGoal(for conversationId: UUID, goal: String) {
        if let idx = conversations.firstIndex(where: { $0.id == conversationId }) {
            conversations[idx].activeGoal = goal
            conversations[idx].goalIterationCount = 0
            saveConversations()
        }
    }
    
    enum ApprovalResolution {
        case approve
        case deny
        case alwaysAllowGlobal
        case alwaysAllowProject
    }
    
    func requestApproval(toolName: String, details: String, workspace: String? = nil) async -> Bool {
        // Fast path: Check deterministic permissions first
        if PermissionManager.shared.isAllowed(toolName: toolName, details: details, workspace: workspace) {
            return true
        }
        
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
            self.pendingApproval = ToolApprovalRequest(toolName: toolName, details: details, workspace: workspace, continuation: continuation)
        }
    }
    
    func resolveApproval(_ resolution: ApprovalResolution) {
        guard let pending = pendingApproval else { return }
        
        var approved = false
        switch resolution {
        case .approve:
            approved = true
        case .deny:
            approved = false
        case .alwaysAllowGlobal:
            PermissionManager.shared.allowGlobally(toolName: pending.toolName, details: pending.details)
            approved = true
        case .alwaysAllowProject:
            if let workspace = pending.workspace {
                PermissionManager.shared.allowInProject(toolName: pending.toolName, details: pending.details, workspace: workspace)
            } else {
                // Fallback to global if no workspace is active
                PermissionManager.shared.allowGlobally(toolName: pending.toolName, details: pending.details)
            }
            approved = true
        }
        
        let cont = pending.continuation
        pendingApproval = nil
        cont.resume(returning: approved)
    }
    
    private var saveTask: Task<Void, Never>? = nil
    
    private func saveConversations() {
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s debounce
            guard !Task.isCancelled else { return }
            if let data = try? JSONEncoder().encode(conversations) {
                UserDefaults.standard.set(data, forKey: "iris_conversations")
            }
        }
    }
    
    func renameConversation(id: UUID, newTitle: String) {
        if let idx = conversations.firstIndex(where: { $0.id == id }) {
            conversations[idx].title = newTitle
            saveConversations()
        }
    }
    
    private func loadConversations() {
        if let data = UserDefaults.standard.data(forKey: "iris_conversations") {
            do {
                let decoded = try JSONDecoder().decode([Conversation].self, from: data)
                self.conversations = decoded
                self.selectedConversationId = decoded.last?.id
            } catch {
                print("Failed to decode conversations: \(error)")
                UserDefaults.standard.set(data, forKey: "iris_conversations_backup_\(Date().timeIntervalSince1970)")
            }
        }
    }
}
