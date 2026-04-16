import Foundation

/// Compatibility delta chunk type retained for existing UI code.
struct ChatStreamChunk: Decodable, Sendable {
    let delta: String
}

enum ChatStreamEvent: Sendable {
    case delta(String)
    case completed(ChatCompletionResponse)
}

struct ChatStreamCompleted: Decodable, Sendable {
    let response: ChatCompletionResponse
}

struct ChatStreamFailed: Decodable, Sendable {
    let response: FailedResponse

    struct FailedResponse: Decodable, Sendable {
        let error: ChatCompletionResponse.ResponseError?
    }
}
