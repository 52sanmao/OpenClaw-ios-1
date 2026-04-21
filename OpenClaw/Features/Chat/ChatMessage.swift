import Foundation

struct ChatMessage: Identifiable, Sendable {
    let id: UUID
    let role: Role
    var content: String
    var isStreaming: Bool
    let timestamp: Date
    var stateText: String?
    let toolCalls: [ToolCall]
    let generatedImages: [GeneratedImage]
    let pendingGate: PendingGate?

    enum Role: Sendable {
        case user
        case assistant
    }

    struct ToolCall: Sendable, Identifiable {
        let id: String
        let name: String
        let hasError: Bool
        let hasResult: Bool
        let resultPreview: String?
        let error: String?
    }

    struct GeneratedImage: Sendable, Identifiable {
        let id: String
        let eventId: String?
        let imageData: Data?
        let path: String?
    }

    struct PendingGate: Sendable {
        let requestId: String?
        let toolName: String?
        let description: String?
        let parametersSummary: String?
        let resumeSummary: String?
        let allowAlways: Bool
    }

    init(
        role: Role,
        content: String,
        isStreaming: Bool = false,
        timestamp: Date = Date(),
        stateText: String? = nil,
        toolCalls: [ToolCall] = [],
        generatedImages: [GeneratedImage] = [],
        pendingGate: PendingGate? = nil
    ) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.isStreaming = isStreaming
        self.timestamp = timestamp
        self.stateText = stateText
        self.toolCalls = toolCalls
        self.generatedImages = generatedImages
        self.pendingGate = pendingGate
    }

    var hasRichContent: Bool {
        !toolCalls.isEmpty || !generatedImages.isEmpty || pendingGate != nil
    }

    var copyableText: String? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
