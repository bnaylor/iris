import Foundation

enum MessageItem: Identifiable {
    case single(ChatMessage)
    case systemGroup(id: UUID, messages: [ChatMessage])
    
    var id: UUID {
        switch self {
        case .single(let msg): return msg.id
        case .systemGroup(let id, _): return id
        }
    }
}
