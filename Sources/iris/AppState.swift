import Foundation
import SwiftUI

enum ChatRole {
    case user
    case agent
    case system
}

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: ChatRole
    let content: String
}

@MainActor
@Observable
class AppState {
    var messages: [ChatMessage] = []
    var isThinking = false
    
    private var engine: IrisEngine!
    
    init() {
        self.engine = IrisEngine(state: self)
    }
    
    func start() {
        Task {
            await engine.start()
        }
    }
    
    func sendMessage(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        appendMessage(role: .user, content: trimmed)
        isThinking = true
        
        Task {
            await engine.processInput(trimmed, source: "UI")
            isThinking = false
        }
    }
    
    func appendMessage(role: ChatRole, content: String) {
        messages.append(ChatMessage(role: role, content: content))
    }
}
