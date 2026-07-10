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

struct Conversation: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var messages: [ChatMessage] = []
    var workspacePath: String?
    var history: [Content] = []
    
    static func == (lhs: Conversation, rhs: Conversation) -> Bool {
        lhs.id == rhs.id
    }
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

@MainActor
@Observable
class AppState {
    var conversations: [Conversation] = []
    var selectedConversationId: UUID?
    var isThinking = false
    
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
    
    func start() {
        Task {
            await engine.start()
        }
    }
    
    func sendMessage(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, activeConversationIndex != nil else { return }
        
        appendMessage(role: .user, content: trimmed, to: selectedConversationId!)
        isThinking = true
        
        let convId = selectedConversationId!
        
        Task {
            await engine.processInput(trimmed, source: "UI", conversationId: convId)
            isThinking = false
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
