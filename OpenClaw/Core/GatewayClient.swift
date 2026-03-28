import Foundation
import os

// MARK: - Protocol (Dependency Inversion)

/// Abstraction over gateway networking — ViewModels depend on this, not concrete types.
protocol GatewayClientProtocol: Sendable {
    func stats<Response: Decodable>(_ path: String) async throws -> Response
    func statsPost<Body: Encodable, Response: Decodable>(_ path: String, body: Body) async throws -> Response
    func invoke<Body: Encodable, Response: Decodable>(_ body: Body) async throws -> Response
    func chatCompletion(_ request: ChatCompletionRequest, sessionKey: String) async throws -> ChatCompletionResponse
    func streamChat(message: String, sessionKey: String) -> AsyncThrowingStream<String, Error>
}

// MARK: - Implementation

/// Thread-safe gateway HTTP client.
/// All stored properties are immutable and Sendable — no @unchecked needed.
struct GatewayClient: GatewayClientProtocol, Sendable {
    private static let baseURL = URL(string: "https://api.appwebdev.co.uk")!
    private static let invokeURL = baseURL.appending(path: "tools/invoke")
    private static let logger = Logger(subsystem: "co.uk.appwebdev.openclaw", category: "Gateway")

    let keychain: KeychainService

    init(keychain: KeychainService = KeychainService()) {
        self.keychain = keychain
    }

    // MARK: - GET /stats/*  (plain JSON, no envelope)

    func stats<Response: Decodable>(_ path: String) async throws -> Response {
        let token = try requireToken()

        guard let url = URL(string: "\(Self.baseURL.absoluteString)/\(path)") else {
            throw GatewayError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        Self.logger.debug("GET /\(path)")

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTPResponse(response, data: data, path: path)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(Response.self, from: data)
    }

    // MARK: - POST /stats/*  (plain JSON, snake_case, e.g. /stats/exec)

    func statsPost<Body: Encodable, Response: Decodable>(_ path: String, body: Body) async throws -> Response {
        let token = try requireToken()

        guard let url = URL(string: "\(Self.baseURL.absoluteString)/\(path)") else {
            throw GatewayError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        Self.logger.debug("POST /\(path)")

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTPResponse(response, data: data, path: path)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(Response.self, from: data)
    }

    // MARK: - POST /tools/invoke  (wrapped: result.content[0].text → JSON string)

    func invoke<Body: Encodable, Response: Decodable>(
        _ body: Body
    ) async throws -> Response {
        let token = try requireToken()

        var request = URLRequest(url: Self.invokeURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        Self.logger.debug("POST /tools/invoke")

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTPResponse(response, data: data, path: "tools/invoke")

        let envelope = try JSONDecoder().decode(GatewayResponse.self, from: data)
        guard let text = envelope.result.content.first?.text,
              let jsonData = text.data(using: .utf8) else {
            throw GatewayError.emptyContent
        }

        return try JSONDecoder().decode(Response.self, from: jsonData)
    }

    // MARK: - POST /v1/chat/completions (with session key header)

    /// Long-running session for chat completions — no timeout (agent may take 15+ minutes).
    private static let longRunningSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 900  // 15 min
        config.timeoutIntervalForResource = 900
        return URLSession(configuration: config)
    }()

    func chatCompletion(_ body: ChatCompletionRequest, sessionKey: String) async throws -> ChatCompletionResponse {
        let token = try requireToken()

        guard let url = URL(string: "\(Self.baseURL.absoluteString)/v1/chat/completions") else {
            throw GatewayError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(sessionKey, forHTTPHeaderField: "x-openclaw-session-key")
        request.httpBody = try JSONEncoder().encode(body)

        Self.logger.debug("POST /v1/chat/completions (session: \(sessionKey))")

        let (data, response) = try await Self.longRunningSession.data(for: request)
        try validateHTTPResponse(response, data: data, path: "v1/chat/completions")

        return try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
    }

    // MARK: - SSE streaming chat

    func streamChat(message: String, sessionKey: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let token = try requireToken()
                    guard let url = URL(string: "\(Self.baseURL.absoluteString)/v1/chat/completions") else {
                        continuation.finish(throwing: GatewayError.invalidResponse)
                        return
                    }

                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue(sessionKey, forHTTPHeaderField: "x-openclaw-session-key")

                    let body = ChatCompletionRequest(
                        system: "", user: message, model: "openclaw", stream: true
                    )
                    request.httpBody = try JSONEncoder().encode(body)

                    Self.logger.debug("SSE /v1/chat/completions (session: \(sessionKey))")

                    let (bytes, response) = try await Self.longRunningSession.bytes(for: request)

                    guard let http = response as? HTTPURLResponse,
                          (200...299).contains(http.statusCode) else {
                        let http = response as? HTTPURLResponse
                        continuation.finish(throwing: GatewayError.httpError(http?.statusCode ?? 0, body: "Stream failed"))
                        return
                    }

                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let payload = String(line.dropFirst(6))
                        if payload == "[DONE]" { break }

                        guard let data = payload.data(using: .utf8),
                              let chunk = try? JSONDecoder().decode(ChatStreamChunk.self, from: data),
                              let delta = chunk.choices.first?.delta.content else {
                            continue
                        }
                        continuation.yield(delta)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Private helpers

    private func requireToken() throws -> String {
        guard let token = keychain.readToken() else {
            throw GatewayError.noToken
        }
        return token
    }

    private func validateHTTPResponse(_ response: URLResponse, data: Data, path: String) throws {
        guard let http = response as? HTTPURLResponse else {
            throw GatewayError.invalidResponse
        }

        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            if let envelope = try? JSONDecoder().decode(GatewayErrorEnvelope.self, from: data),
               let detail = envelope.error {
                Self.logger.error("\(http.statusCode) /\(path) — \(detail.message)")
                throw GatewayError.serverError(http.statusCode, type: detail.type, message: detail.message)
            }
            Self.logger.error("\(http.statusCode) /\(path)")
            throw GatewayError.httpError(http.statusCode, body: body)
        }
    }
}
