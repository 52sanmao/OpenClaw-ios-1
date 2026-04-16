import Foundation

/// Compatibility request used by view models; `GatewayClient` maps it onto IronClaw thread APIs.
struct ChatCompletionRequest: Encodable, Sendable {
    let model: String
    let input: [InputItem]
    let instructions: String?
    let previousResponseId: String?
    let stream: Bool

    struct InputItem: Encodable, Sendable {
        let type = "message"
        let role: String
        let content: String
    }

    init(
        system: String,
        user: String,
        model: String = "default",
        previousResponseId: String? = nil,
        stream: Bool = false
    ) {
        self.model = model
        self.instructions = system.isEmpty ? nil : system
        self.previousResponseId = previousResponseId
        self.stream = stream
        self.input = [InputItem(role: "user", content: user)]
    }

    enum CodingKeys: String, CodingKey {
        case model, input, instructions, stream
        case previousResponseId = "previous_response_id"
    }
}

/// Compatibility response shape synthesized from IronClaw thread results.
struct ChatCompletionResponse: Decodable, Sendable {
    let id: String?
    let model: String?
    let output: [OutputItem]?
    let usage: Usage?
    let error: ResponseError?

    struct OutputItem: Decodable, Sendable {
        let type: String?
        let role: String?
        let content: [ContentItem]?
    }

    struct ContentItem: Decodable, Sendable {
        let type: String?
        let text: String?
    }

    struct Usage: Decodable, Sendable {
        let inputTokens: Int?
        let outputTokens: Int?
        let totalTokens: Int?

        enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
            case totalTokens = "total_tokens"
        }

        var promptTokens: Int? { inputTokens }
        var completionTokens: Int? { outputTokens }
    }

    struct ResponseError: Decodable, Sendable {
        let code: String?
        let message: String?
    }

    var text: String? {
        let segments = (output ?? []).flatMap { item -> [String] in
            let content = item.content ?? []
            return content.compactMap { part in
                guard part.type == "output_text" || part.type == "text" else { return nil }
                return part.text
            }
        }
        let value = segments.joined()
        return value.isEmpty ? nil : value
    }
}

struct ResponsesEnvelope: Decodable, Sendable {
    let response: ChatCompletionResponse
}

struct ResponseFailureEnvelope: Decodable, Sendable {
    let response: FailedResponse

    struct FailedResponse: Decodable, Sendable {
        let error: ChatCompletionResponse.ResponseError?
    }
}

struct ResponsesTextDelta: Decodable, Sendable {
    let delta: String
}

struct ResponsesModelsEnvelope: Decodable, Sendable {
    let data: [ResponsesModelEntry]?
}

struct ResponsesModelEntry: Decodable, Sendable {
    let id: String
}

struct ChatThreadListResponse: Decodable, Sendable {
    let assistantThread: ChatThreadInfo?
    let threads: [ChatThreadInfo]
    let activeThread: String?

    enum CodingKeys: String, CodingKey {
        case assistantThread = "assistant_thread"
        case threads
        case activeThread = "active_thread"
    }
}

struct ChatThreadInfo: Decodable, Sendable {
    let id: String
    let state: String?
    let turnCount: Int?
    let createdAt: String?
    let updatedAt: String?
    let title: String?
    let threadType: String?
    let channel: String?

    enum CodingKeys: String, CodingKey {
        case id, state, title, channel
        case turnCount = "turn_count"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case threadType = "thread_type"
    }
}

struct ChatThreadHistoryResponse: Decodable, Sendable {
    let threadId: String
    let turns: [ChatThreadTurn]
    let hasMore: Bool

    enum CodingKeys: String, CodingKey {
        case threadId = "thread_id"
        case turns
        case hasMore = "has_more"
    }
}

struct ChatThreadTurn: Decodable, Sendable {
    let turnNumber: Int?
    let userInput: String
    let response: String?
    let state: String
    let startedAt: String?
    let completedAt: String?

    enum CodingKeys: String, CodingKey {
        case turnNumber = "turn_number"
        case userInput = "user_input"
        case response, state
        case startedAt = "started_at"
        case completedAt = "completed_at"
    }

    var isTerminal: Bool {
        let normalized = state.lowercased()
        return normalized.contains("completed") || normalized.contains("failed") || normalized.contains("accepted")
    }
}

struct ChatSendRequest: Encodable, Sendable {
    let content: String
    let threadId: String?
    let timezone: String?

    enum CodingKeys: String, CodingKey {
        case content, timezone
        case threadId = "thread_id"
    }
}

struct ChatSendResponse: Decodable, Sendable {
    let messageId: String?
    let status: String?

    enum CodingKeys: String, CodingKey {
        case messageId = "message_id"
        case status
    }
}

struct ChatStreamPollResult: Sendable {
    let history: ChatThreadHistoryResponse
    let latestTurn: ChatThreadTurn
}
