import Foundation
import os

// MARK: - Protocol (Dependency Inversion)

/// Abstraction over gateway networking — ViewModels depend on this, not concrete types.
protocol GatewayClientProtocol: Sendable {
    func stats<Response: Decodable>(_ path: String) async throws -> Response
    func statsPost<Body: Encodable, Response: Decodable>(_ path: String, body: Body) async throws -> Response
    func invoke<Body: Encodable, Response: Decodable>(_ body: Body) async throws -> Response
    func chatCompletion(_ request: ChatCompletionRequest) async throws -> ChatCompletionResponse
    func streamChat(message: String, previousResponseId: String?) -> AsyncThrowingStream<ChatStreamEvent, Error>
    func listChatThreads() async throws -> ChatThreadListResponse
    func createChatThread() async throws -> ChatThreadInfo
    func loadChatHistory(threadId: String) async throws -> ChatThreadHistoryResponse
    func sendThreadMessage(threadId: String, content: String) async throws -> ChatSendResponse
    func waitForThreadTurn(threadId: String, afterTurnCount: Int, timeout: TimeInterval) async throws -> ChatStreamPollResult
    func validateConnection() async throws
}

private struct MappedThreadCompletion {
    let response: ChatCompletionResponse
    let threadId: String
}

// MARK: - Implementation

/// Thread-safe HTTP client. Configured with a base URL and token.
struct GatewayClient: GatewayClientProtocol, Sendable {
    private static let logger = Logger(subsystem: "co.uk.appwebdev.openclaw", category: "Gateway")

    private static let longRunningSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 900
        return URLSession(configuration: config)
    }()

    private let baseURL: URL
    private let token: String

    init(baseURL: URL, token: String) {
        self.baseURL = baseURL
        self.token = token
    }

    /// Convenience init from AccountStore.
    init?(accountStore: AccountStore) {
        guard let url = accountStore.activeBaseURL(),
              let token = accountStore.activeToken() else { return nil }
        self.init(baseURL: url, token: token)
    }

    // MARK: - GET /stats/*

    func stats<Response: Decodable>(_ path: String) async throws -> Response {
        let (data, _) = try await request("GET", path: path)
        return try JSONDecoder.snakeCase.decode(Response.self, from: data)
    }

    // MARK: - POST /stats/*

    func statsPost<Body: Encodable, Response: Decodable>(_ path: String, body: Body) async throws -> Response {
        let bodyData = try JSONEncoder().encode(body)
        let (data, _) = try await request("POST", path: path, body: bodyData)
        return try JSONDecoder.snakeCase.decode(Response.self, from: data)
    }

    func invoke<Body: Encodable, Response: Decodable>(_ body: Body) async throws -> Response {
        let requestBody = try JSONEncoder().encode(body)
        return try await invokeRaw(method: "invoke", body: requestBody)
    }

    func chatCompletion(_ request: ChatCompletionRequest) async throws -> ChatCompletionResponse {
        let mapped = try await performThreadCompletion(
            system: request.instructions ?? "",
            user: request.input.first?.content ?? "",
            requestedThreadId: request.previousResponseId,
            stream: request.stream
        )
        return mapped.response
    }

    // MARK: - Thread-based chat

    func streamChat(message: String, previousResponseId: String?) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let mapped = try await performThreadCompletion(
                        system: "",
                        user: message,
                        requestedThreadId: previousResponseId,
                        stream: true
                    )
                    if let text = mapped.response.text, !text.isEmpty {
                        continuation.yield(.delta(text))
                    }
                    continuation.yield(.completed(mapped.response))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func performThreadCompletion(
        system: String,
        user: String,
        requestedThreadId: String?,
        stream: Bool
    ) async throws -> MappedThreadCompletion {
        _ = stream
        let normalizedUser = user.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedUser.isEmpty else {
            throw GatewayError.invalidResponse
        }

        let threadId = try await resolveThreadId(requestedThreadId)
        let baselineHistory = try await loadChatHistory(threadId: threadId)
        let content = composeThreadMessage(system: system, user: normalizedUser)

        Self.logger.debug("POST /api/chat/send (thread_id: \(threadId))")
        _ = try await sendThreadMessage(threadId: threadId, content: content)

        let poll = try await waitForThreadTurn(
            threadId: threadId,
            afterTurnCount: baselineHistory.turns.count,
            timeout: 45
        )

        let latest = poll.latestTurn
        if latest.state.lowercased().contains("failed") {
            throw GatewayError.serverError(500, type: "thread_failed", message: latest.response ?? "IronClaw 线程响应失败。")
        }

        let response = ChatCompletionResponse(
            id: threadId,
            model: nil,
            output: mappedOutput(text: latest.response),
            usage: nil,
            error: nil
        )
        return MappedThreadCompletion(response: response, threadId: threadId)
    }

    private func resolveThreadId(_ requestedThreadId: String?) async throws -> String {
        if let requestedThreadId {
            let trimmed = requestedThreadId.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return try await createChatThread().id
    }

    private func composeThreadMessage(system: String, user: String) -> String {
        let normalizedSystem = system.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedSystem.isEmpty {
            return user
        }
        return "系统指令:\n\(normalizedSystem)\n\n用户消息:\n\(user)"
    }

    private func mappedOutput(text: String?) -> [ChatCompletionResponse.OutputItem]? {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return [
            ChatCompletionResponse.OutputItem(
                type: "message",
                role: "assistant",
                content: [
                    ChatCompletionResponse.ContentItem(type: "output_text", text: text)
                ]
            )
        ]
    }

    // MARK: - Thread APIs

    func listChatThreads() async throws -> ChatThreadListResponse {
        let (data, _) = try await request("GET", path: "api/chat/threads")
        return try JSONDecoder.snakeCase.decode(ChatThreadListResponse.self, from: data)
    }

    func createChatThread() async throws -> ChatThreadInfo {
        let (data, _) = try await request("POST", path: "api/chat/thread/new")
        return try JSONDecoder.snakeCase.decode(ChatThreadInfo.self, from: data)
    }

    func loadChatHistory(threadId: String) async throws -> ChatThreadHistoryResponse {
        let escaped = threadId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? threadId
        let (data, _) = try await request("GET", path: "api/chat/history?thread_id=\(escaped)")
        return try JSONDecoder.snakeCase.decode(ChatThreadHistoryResponse.self, from: data)
    }

    func sendThreadMessage(threadId: String, content: String) async throws -> ChatSendResponse {
        let body = try JSONEncoder().encode(
            ChatSendRequest(
                content: content,
                threadId: threadId,
                timezone: TimeZone.current.identifier
            )
        )
        let (data, _) = try await request("POST", path: "api/chat/send", body: body)
        return try JSONDecoder.snakeCase.decode(ChatSendResponse.self, from: data)
    }

    func waitForThreadTurn(threadId: String, afterTurnCount: Int, timeout: TimeInterval = 30) async throws -> ChatStreamPollResult {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let history = try await loadChatHistory(threadId: threadId)
            if let latest = history.turns.last,
               history.turns.count > afterTurnCount,
               latest.isTerminal {
                return ChatStreamPollResult(history: history, latestTurn: latest)
            }
            try await Task.sleep(nanoseconds: 300_000_000)
        }
        throw GatewayError.httpError(408, body: "Timed out waiting for IronClaw thread response")
    }

    func validateConnection() async throws {
        let token = try requireToken()
        let url = try buildURL("v1/models")
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        Self.logger.debug("GET /v1/models")
        let (data, response) = try await URLSession.shared.data(for: req)
        try validateHTTPResponse(response, data: data, path: "v1/models")
    }

    // MARK: - Private helpers

    private func request(_ method: String, path: String, body: Data? = nil) async throws -> (Data, URLResponse) {
        let token = try requireToken()
        let url = try buildURL(path)
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = body
        }
        Self.logger.debug("\(method) /\(path)")
        let (data, response) = try await URLSession.shared.data(for: req)
        try validateHTTPResponse(response, data: data, path: path)
        return (data, response)
    }

    private func invokeRaw<Response: Decodable>(method: String, body: Data) async throws -> Response {
        let token = try requireToken()
        let url = try buildURL("tools/invoke")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        Self.logger.debug("POST /tools/invoke [\(method)]")
        let (data, response) = try await URLSession.shared.data(for: req)
        try validateHTTPResponse(response, data: data, path: "tools/invoke")
        return try JSONDecoder().decode(Response.self, from: data)
    }

    private func requireToken() throws -> String {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw GatewayError.noToken }
        return trimmed
    }

    private func buildURL(_ path: String) throws -> URL {
        let trimmedBase = baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let trimmedPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(trimmedBase)/\(trimmedPath)") else { throw GatewayError.invalidResponse }
        return url
    }

    private func validateHTTPResponse(_ response: URLResponse, data: Data, path: String) throws {
        guard let http = response as? HTTPURLResponse else { throw GatewayError.invalidResponse }
        let body = String(data: data, encoding: .utf8) ?? ""

        if (200...299).contains(http.statusCode) {
            if isLikelyControlPage(body, response: http) {
                throw GatewayError.controlPageReturned(path: path)
            }
            return
        }

        if let envelope = try? JSONDecoder().decode(GatewayErrorEnvelope.self, from: data), let err = envelope.error {
            throw GatewayError.serverError(http.statusCode, type: err.type, message: err.message)
        }
        throw GatewayError.httpError(http.statusCode, body: body)
    }

    private func isLikelyControlPage(_ body: String, response: HTTPURLResponse) -> Bool {
        let contentType = response.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
        let sample = body.prefix(512).lowercased()
        guard contentType.contains("text/html") || sample.contains("<!doctype html") || sample.contains("<html") else {
            return false
        }

        return sample.contains("openclaw") ||
               sample.contains("hermes") ||
               sample.contains("control ui") ||
               sample.contains("<head") ||
               sample.contains("<body")
    }
}

private extension JSONDecoder {
    static let snakeCase: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()
}
