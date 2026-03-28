import Foundation

struct ChatMessage: Identifiable, Sendable {
    let id: UUID
    let role: Role
    var content: String
    var isStreaming: Bool

    enum Role: Sendable {
        case user
        case assistant
    }

    init(role: Role, content: String, isStreaming: Bool = false) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.isStreaming = isStreaming
    }
}
