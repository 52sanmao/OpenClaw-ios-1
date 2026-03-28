import Foundation

/// Request body for /v1/chat/completions.
struct ChatCompletionRequest: Encodable, Sendable {
    let model: String
    let messages: [Message]
    let stream: Bool

    struct Message: Encodable, Sendable {
        let role: String
        let content: String
    }

    init(system: String, user: String, model: String = "openclaw", stream: Bool = false) {
        self.model = model
        self.stream = stream
        var msgs: [Message] = []
        if !system.isEmpty { msgs.append(Message(role: "system", content: system)) }
        msgs.append(Message(role: "user", content: user))
        self.messages = msgs
    }
}

/// Response from /v1/chat/completions (non-streaming).
struct ChatCompletionResponse: Decodable, Sendable {
    let choices: [Choice]
    let usage: Usage?
    let model: String?

    struct Choice: Decodable, Sendable {
        let message: Message
    }

    struct Message: Decodable, Sendable {
        let content: String?
    }

    struct Usage: Decodable, Sendable {
        let promptTokens: Int?
        let completionTokens: Int?
        let totalTokens: Int?

        enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
            case totalTokens = "total_tokens"
        }
    }

    var text: String? {
        choices.first?.message.content
    }
}
