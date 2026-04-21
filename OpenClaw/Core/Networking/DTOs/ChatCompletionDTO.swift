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

struct ChatThreadInfo: Decodable, Sendable, Identifiable {
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
    let pendingGate: ChatPendingGateDTO?

    enum CodingKeys: String, CodingKey {
        case threadId = "thread_id"
        case turns
        case hasMore = "has_more"
        case pendingGate = "pending_gate"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        threadId = try container.decodeIfPresent(String.self, forKey: .threadId) ?? ""
        turns = try container.decodeIfPresent([ChatThreadTurn].self, forKey: .turns) ?? []
        hasMore = try container.decodeIfPresent(Bool.self, forKey: .hasMore) ?? false
        pendingGate = try container.decodeIfPresent(ChatPendingGateDTO.self, forKey: .pendingGate)
    }
}

struct ChatPendingGateDTO: Decodable, Sendable {
    let requestId: String?
    let toolName: String?
    let description: String?
    let parameters: [String: JSONValue]?
    let resumeKind: JSONValue?
    let threadId: String?
    let allowAlways: Bool?

    enum CodingKeys: String, CodingKey {
        case requestId = "request_id"
        case toolName = "tool_name"
        case description
        case parameters
        case resumeKind = "resume_kind"
        case threadId = "thread_id"
        case allowAlways = "allow_always"
    }
}

struct ChatThreadTurn: Decodable, Sendable {
    let turnNumber: Int?
    let userInput: String
    let response: String?
    let state: String
    let startedAt: String?
    let completedAt: String?
    let toolCalls: [ChatToolCallDTO]?
    let generatedImages: [ChatGeneratedImageDTO]?

    enum CodingKeys: String, CodingKey {
        case turnNumber = "turn_number"
        case userInput = "user_input"
        case response, state
        case startedAt = "started_at"
        case completedAt = "completed_at"
        case toolCalls = "tool_calls"
        case generatedImages = "generated_images"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        turnNumber = try container.decodeIfPresent(Int.self, forKey: .turnNumber)
        userInput = try container.decodeIfPresent(String.self, forKey: .userInput) ?? ""
        response = try container.decodeIfPresent(String.self, forKey: .response)
        state = try container.decodeIfPresent(String.self, forKey: .state) ?? ""
        startedAt = try container.decodeIfPresent(String.self, forKey: .startedAt)
        completedAt = try container.decodeIfPresent(String.self, forKey: .completedAt)
        toolCalls = try container.decodeIfPresent([ChatToolCallDTO].self, forKey: .toolCalls)
        generatedImages = try container.decodeIfPresent([ChatGeneratedImageDTO].self, forKey: .generatedImages)
    }

    var isTerminal: Bool {
        let normalized = state.lowercased()
        return normalized.contains("completed") || normalized.contains("done") || normalized.contains("failed")
    }
}

struct ChatToolCallDTO: Decodable, Sendable, Identifiable {
    let id: String
    let name: String
    let hasError: Bool
    let hasResult: Bool
    let resultPreview: String?
    let error: String?

    enum CodingKeys: String, CodingKey {
        case id, name, error
        case hasError = "has_error"
        case hasResult = "has_result"
        case resultPreview = "result_preview"
    }
}

struct ChatGeneratedImageDTO: Decodable, Sendable, Identifiable {
    let id: String
    let eventId: String?
    let dataUrl: String?
    let path: String?

    enum CodingKeys: String, CodingKey {
        case id, path
        case eventId = "event_id"
        case dataUrl = "data_url"
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
