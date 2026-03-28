import Foundation

/// SSE delta chunk from streaming /v1/chat/completions.
struct ChatStreamChunk: Decodable, Sendable {
    let choices: [Choice]

    struct Choice: Decodable, Sendable {
        let delta: Delta
    }

    struct Delta: Decodable, Sendable {
        let content: String?
    }
}
